using Toybox.WatchUi;
using Toybox.AntPlus;
using Toybox.Sensor;
using Toybox.Position;
using Toybox.FitContributor;

class MyBikeTrafficView extends WatchUi.SimpleDataField {

	// radar related attributes
	var bikeRadar;  
	
	// vehicle count related attributes
	// raw count of number of vehicles
	var count=0;
	var lasttrackcnt=0;
	var crossedthresh = false;  // this is a flag to indicate that the closest car has approached within THRESH distance and should be counted when it disappears off radar 
	const THRESH=30; 			// this is the threshold distance that the closest car must be in order for it to be counted

	// datafield attributes and constants for custom data written into FIT files
	var rangeDataField;
	var speedDataField;
	var countDataField;
	var passingSpeedDataFieldKPH;
	var passingSpeedDataFieldMPH;
//	var threatDataField;
//	var threatsideDataField; 

	const RANGETARGETS=8;
	const SPEEDTARGETS=8;
	
	const BT_RANGE_FIELD_ID = 0; // range floats
	const BT_SPEED_FIELD_ID = 1; // speed floats
	const BT_COUNT_FIELD_ID = 2; // current total count
	const BT_PASSINGSPEED_KPH_FIELD_ID = 3; // speed of closest car (KPH) ... 0 if no cars currently on radar being tracked
	const BT_PASSINGSPEED_MPH_FIELD_ID = 4; // speed of closest car (MPH) ... 0 if no cars currently on radar being tracked
//	const BT_THREAT_FIELD_ID = 4;  threat level bytes, 0-no threat,1-approaching,2-fast approaching
//	const BT_THREATSIDE_FIELD_ID = 5; 	threat side 0-left, 1-right
	
    // Set the label of the data field here.
	// Initialize all custom data fields for FIT recording
	// Initialize the bikeRadar object to get the data coming from the radar
    function initialize() {
        SimpleDataField.initialize();
        label = "VehicleCount";
		bikeRadar = new AntPlus.BikeRadar(null); // no need for listener b/c listener only fires at same rate as compute method
		rangeDataField = createField(
            "radar_ranges",
            BT_RANGE_FIELD_ID,
            FitContributor.DATA_TYPE_SINT16,
            {:count=>RANGETARGETS,:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		speedDataField = createField(
            "radar_speeds",
            BT_SPEED_FIELD_ID,
            FitContributor.DATA_TYPE_UINT8,
            {:count=>SPEEDTARGETS,:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		countDataField = createField(
            "radar_current",
            BT_COUNT_FIELD_ID,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		passingSpeedDataFieldMPH = createField( 
            "passing_speed",
            BT_PASSINGSPEED_MPH_FIELD_ID,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		passingSpeedDataFieldKPH = createField(
            "passing_speed",
            BT_PASSINGSPEED_KPH_FIELD_ID,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
// not enough room to store this data ... field limited to 32 bytes of data per message ... 8*2 + 8*1 + 1*2 + 2*1 = 28 bytes ... so technically we can store the threat level for 4 cars using single byte ... maybe next version?
//		threatDataField = createField(
//            "radar_threats",
//            BT_THREAT_FIELD_ID,
//            FitContributor.DATA_TYPE_UINT8,
//            {:count=>6,:mesgType=>FitContributor.MESG_TYPE_RECORD}
//        );
//		threatsideDataField = createField(
//            "radar_threatsides",
//            BT_THREATSIDE_FIELD_ID,
//            FitContributor.DATA_TYPE_UINT8,
//            {:count=>8,:mesgType=>FitContributor.MESG_TYPE_RECORD}
//        );
    }
    
    // The given info object contains all the current workout information (speed, cad, hr, etc...)
    //
    // Radar algorithm -
    //   counting ... 
    //		check how many targets we were tracking last update ... 
    //   	if number has gone up and range is within threshold meters then set thresh flag and increment count when count goes back down 
    //      ... false negatives - missed cars when another car appears right when car passes so that current tracking count never goes down which is the cue to increment total count ... since the incoming car exactly replaces the passings car, the number of cars tracked never changes ... happens primarily on busy roads
    //   	... false positives - car could come in range but then turn well before reaching us ... UPDATE - addressed with threshold param
    ///  storing custom data fields ...
    //   	encode 7 range targets and 7 speed targets but convert to 16bit signed integer instead of float b/c total data per record limited to 32bytes
 
    // start here - convert floats to two byte ints
    function compute(info) { 
        var radarInfo = bikeRadar.getRadarInfo();

    	// do nothing if activity is not running
    	// just return the current count
    	if (info.timerState != 3) {
    		if (radarInfo) {
    			return count;
    		} else {
    			return "--";
    		} 
    	}

		var rangeInfo = new [RANGETARGETS];
		var speedInfo = new [SPEEDTARGETS];
        if (radarInfo) {
			for (var i=0;i<RANGETARGETS;i++) {
			  rangeInfo[i] = radarInfo[i].range.toNumber();
			}
			for (var i=0;i<SPEEDTARGETS;i++) {
		  	  speedInfo[i] = radarInfo[i].speed.toNumber();
			}
			rangeDataField.setData(rangeInfo);
			speedDataField.setData(speedInfo);

			// this will cause speed to be 0 when no cars tracked which is perfect
	  		passingSpeedDataFieldKPH.setData(Math.round(speedInfo[0]*3.6));
	  		passingSpeedDataFieldMPH.setData(Math.round(speedInfo[0]*2.23694));

			var trackcnt = 0;
        	for(var i=0;i<radarInfo.size();i++) {
        	  if(radarInfo[i].threat!=0) {
        	  	trackcnt++;
		 	  }		 
			}			
			if (trackcnt<lasttrackcnt) {
				// car has disappeared, so if we should count it if it crossed the threshold of "closeness" before disappearing
				if (crossedthresh) {
					count = count + (lasttrackcnt-trackcnt);
				}
			}
			crossedthresh = rangeInfo[0] < THRESH;
			lasttrackcnt=trackcnt;
			countDataField.setData(count);			
	        return count;
		} else {
			// only way to indicate when the radar isn't active is to set the range and speed to bogus (negative) values
			// this prevents us from false negatives in our mapping where we would include "zero cars" on a stretch
			// of road that actually had a bunch of cars, but the radar was off.
			for (var i=0;i<RANGETARGETS;i++) {
			  rangeInfo[i] = -1;  // can keep this one as signed since taking up two bytes anyway ... so -1 still the "bogus" radar disabled value
			}
			for (var i=0;i<SPEEDTARGETS;i++) {
		  	  speedInfo[i] = 255; // needed to update to unsigned so I can just use single byte ... consequently 255 is now the "bogus" value
			}
			rangeDataField.setData(rangeInfo);
			speedDataField.setData(speedInfo);
			countDataField.setData(count);	
			passingSpeedDataFieldKPH.setData(0); 		
			passingSpeedDataFieldMPH.setData(0); 		
			return "--";
		}		
    }
    
    // activity has ended
    // handle resetting count to 0 after activity has ended
    function onTimerReset() {
		count=0;
		lasttrackcnt=0;
		crossedthresh = false;
    }
    
}