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
	var lapcount=0;
	var count=0;
	var lasttrackcnt=0;
	var crossedthresh = false;  // this is a flag to indicate that the closest car has approached within THRESH distance and should be counted when it disappears off radar 
	const THRESH=30; 			// this is the threshold distance that the closest car must be in order for it to be counted

	// datafield attributes and constants for custom data written into FIT files
	var rangeDataField;
	var speedDataField;
	var countDataField;
	var countSessionField;
	var countLapField;
	var passingSpeedDataField;
	var metric = true;
//	var passingSpeedDataFieldMPH;
//	var passingSpeedDataFieldMPH;
//	var threatDataField;
//	var threatsideDataField; 

	const RANGETARGETS=8;
	const SPEEDTARGETS=8;
	
	const BT_RANGE_FIELD_ID = 0; // range floats
	const BT_SPEED_FIELD_ID = 1; // speed floats
	const BT_COUNT_FIELD_ID = 2; // current total count
	const BT_COUNT_SESSION_FIELD_ID = 3; // current total count (same as regular count but the session field for activity summary)
	const BT_COUNT_LAP_FIELD_ID = 4; // current lap count
	const BT_PASSINGSPEED_KPH_FIELD_ID = 5; // speed of closest car (KPH) ... 0 if no cars currently on radar being tracked
	const BT_PASSINGSPEED_MPH_FIELD_ID = 6; // speed of closest car (MPH) ... 0 if no cars currently on radar being tracked
//	const BT_THREAT_FIELD_ID = 4;  threat level bytes, 0-no threat,1-approaching,2-fast approaching
//	const BT_THREATSIDE_FIELD_ID = 5; 	threat side 0-left, 1-right
	
    // Set the label of the data field here.
	// Initialize all custom data fields for FIT recording
	// Initialize the bikeRadar object to get the data coming from the radar
    function initialize() {
        SimpleDataField.initialize();
        label = "VehicleCount";
		bikeRadar = new AntPlus.BikeRadar(null); // no need for listener b/c listener only fires at same rate as compute method
		rangeDataField = createField( // 16 bytes
            "radar_ranges",
            BT_RANGE_FIELD_ID,
            FitContributor.DATA_TYPE_SINT16,
            {:count=>RANGETARGETS,:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		speedDataField = createField( // 8 bytes
            "radar_speeds",
            BT_SPEED_FIELD_ID,
            FitContributor.DATA_TYPE_UINT8,
            {:count=>SPEEDTARGETS,:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		countDataField = createField( // 2 bytes
            "radar_current",			
            BT_COUNT_FIELD_ID,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		countSessionField = createField( // 2 bytes
            "radar_total",
            BT_COUNT_SESSION_FIELD_ID,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_SESSION}
        );
		countLapField = createField( // 2 bytes
            "radar_lap",
            BT_COUNT_LAP_FIELD_ID,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_LAP}
        );
        var sys = System.getDeviceSettings();
        if (sys.distanceUnits == System.UNIT_STATUTE) {
        	metric = false;
			passingSpeedDataField = createField( // 1 byte (either this one or the else clause)
	            "passing_speed",
	            BT_PASSINGSPEED_MPH_FIELD_ID,
	            FitContributor.DATA_TYPE_UINT8,
	            {:mesgType=>FitContributor.MESG_TYPE_RECORD}
	        );
	    } else {
			passingSpeedDataField = createField( // 1 byte (either this one or the if clause)
	            "passing_speed",
	            BT_PASSINGSPEED_KPH_FIELD_ID,
	            FitContributor.DATA_TYPE_UINT8,
	            {:mesgType=>FitContributor.MESG_TYPE_RECORD}
	        );
        }
        
        // data total: 8*2(ranges) + 8*1(speeds) + 3*2(count record, count session, count lap) + 1*1(passing speed) = 31 bytes ... 1 byte left to do something with
        
// not enough room to store this data ... field limited to 32 bytes of data per message ... 
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
			if (metric) {
	  			passingSpeedDataField.setData(Math.round(speedInfo[0]*3.6));
	  		} else {
	  			passingSpeedDataField.setData(Math.round(speedInfo[0]*2.23694));
	  		}

			var trackcnt = 0;
        	for(var i=0;i<radarInfo.size();i++) {
        	  if(radarInfo[i].threat!=0) {
        	  	trackcnt++;
		 	  }		 
			}			
			if (trackcnt<lasttrackcnt) {
				// car has disappeared, so if we should count it if it crossed the threshold of "closeness" before disappearing
				// also, there is no difference in how counting works for total vs lap ... just need to reset lap count whenever lap button pressed
				if (crossedthresh) {
					count = count + (lasttrackcnt-trackcnt);
					lapcount = lapcount + (lasttrackcnt-trackcnt);
				}
			}
			crossedthresh = rangeInfo[0] < THRESH;
			lasttrackcnt=trackcnt;
			countDataField.setData(count);			
			countLapField.setData(lapcount);			
			countSessionField.setData(count);			
	        return count;
		} else {
			// only way to indicate when the radar isn't active is to set the range and speed to bogus (negative) values
			// this prevents us from false negatives in our mapping where we would include "zero cars" on a stretch
			// of road that actually had a bunch of cars, but the radar was off.
			for (var i=0;i<RANGETARGETS;i++) {
			  rangeInfo[i] = -1;  // can keep this one as signed since taking up two bytes anyway ... so -1 still the "bogus" radar disabled value
			  speedInfo[i] = 255;
			}
			rangeDataField.setData(rangeInfo);
			speedDataField.setData(speedInfo);
			countDataField.setData(count);	
			countLapField.setData(lapcount);			
			countSessionField.setData(count);			
			passingSpeedDataField.setData(0); 		
			return "--";
		}		
    }
    
    // activity has ended
    // handle resetting count to 0 after activity has ended
    function onTimerReset() {
		count=0;
		lapcount=0;
		lasttrackcnt=0;
		crossedthresh = false;
    }
    
    // simply reset the lapcount ... lap data already written out once per second (per documentation) overwriting previous lap message ... this is the way it's supposed to work!
    function onTimerLap() {
    	lapcount = 0;
    }
    
}