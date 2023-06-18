using Toybox.WatchUi;
using Toybox.FitContributor;
using Toybox.Sensor;
using Toybox.AntPlus;

class MyBikeTrafficFitContributions {

	// radar related attributes
	var bikeRadar;  
	
	// vehicle count related attributes
	// raw count of number of vehicles
	// public vars are directly accessed by the datafield for display purposes
	var lapcount;
	var count;
	var approachspd; // relative speed only
	var absolutespd; // relative speed PLUS rider speed = absolute vehicle spd
	var lastspd;     // absolute speed only (relative + rider)... not reset between cars
	var dist;        // distance to closest car (convert to feet if not metric)
	var disabled;
	hidden var lasttrackcnt;
	hidden var crossedthresh;  // this is a flag to indicate that the closest car has approached within THRESH distance and should be counted when it disappears off radar 
	const THRESH=30; 			// this is the threshold distance that the closest car must be in order for it to be counted
	const RANGETARGETS=8;
	const SPEEDTARGETS=8;

	hidden var metric = true;

	// datafield attributes and constants for custom data written into FIT files
	var rangeDataField;
	var speedDataField;
	var countDataField;
	var countSessionField;
	var countLapField;
	var passingSpeedRelDataField;
	var passingSpeedAbsDataField;

	const BT_RANGE_FIELD_ID = 0; // range floats
	const BT_SPEED_FIELD_ID = 1; // speed floats
	const BT_COUNT_FIELD_ID = 2; // current total count
	const BT_COUNT_SESSION_FIELD_ID = 3; // current total count (same as regular count but the session field for activity summary)
	const BT_COUNT_LAP_FIELD_ID = 4; // current lap count
	const BT_PASSINGSPEEDREL_FIELD_ID = 5; // relative speed of closest car (units based on device settings) ... 0 if no cars currently on radar being tracked
	const BT_PASSINGSPEEDABS_FIELD_ID = 6; // absolute speed of closest car (units based on device settings) ... 0 if no cars currently on radar being tracked 
//	const BT_THREAT_FIELD_ID = 4;  threat level bytes, 0-no threat,1-approaching,2-fast approaching
//	const BT_THREATSIDE_FIELD_ID = 5; 	threat side 0-left, 1-right
	
    function initialize(datafield, metric) {
        self.metric = metric;
		bikeRadar = new AntPlus.BikeRadar(null);
        lapcount = 0;
        count = 0;
        lasttrackcnt = 0;
        approachspd = 0;
        absolutespd = 0;
		lastspd = 0;
		dist = 0;
        crossedthresh = false;
        disabled = true;
		rangeDataField = datafield.createField( // 16 bytes
            "radar_ranges",
            BT_RANGE_FIELD_ID,
            FitContributor.DATA_TYPE_SINT16,
            {:count=>RANGETARGETS,:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		speedDataField = datafield.createField( // 8 bytes
            "radar_speeds",
            BT_SPEED_FIELD_ID,
            FitContributor.DATA_TYPE_UINT8,
            {:count=>SPEEDTARGETS,:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		countDataField = datafield.createField( // 2 bytes
            "radar_current",			
            BT_COUNT_FIELD_ID,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		countSessionField = datafield.createField( // 2 bytes
            "radar_total",
            BT_COUNT_SESSION_FIELD_ID,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_SESSION}
        );
		countLapField = datafield.createField( // 2 bytes
            "radar_lap",
            BT_COUNT_LAP_FIELD_ID,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_LAP}
        );
		passingSpeedRelDataField = datafield.createField( // 1 byte (either this one or the if clause)
            "passing_speed",
            BT_PASSINGSPEEDREL_FIELD_ID,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		passingSpeedAbsDataField = datafield.createField( // 1 byte (either this one or the if clause)
            "passing_speedabs",
            BT_PASSINGSPEEDABS_FIELD_ID,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
    }
   
    // The given info object contains all the current workout information.
    // Calculate a value and save it locally in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info) {
    	// do nothing if activity is not running
		// simply set flag that radar is disabled if the timer is not running ... technically the radar MAY be enabled, but we don't care b/c we don't want to write into the FIT file while the timer is not running
		if (info.timerState!=3) {
			disabled = true;
			return;  // nothing else to do, let's get out of here ... 
		} 
        var radarInfo = bikeRadar.getRadarInfo();
		var rangeInfo = new [RANGETARGETS];
		var speedInfo = new [SPEEDTARGETS];
        if (radarInfo) {
        	disabled = false;
			for (var i=0;i<RANGETARGETS;i++) {
			  rangeInfo[i] = radarInfo[i].range.toNumber();
			}
			for (var i=0;i<SPEEDTARGETS;i++) {
		  	  speedInfo[i] = radarInfo[i].speed.toNumber();
			}
			approachspd = metric ? Math.round(speedInfo[0] * 3.6) : Math.round(speedInfo[0] * 2.23694);
			absolutespd = approachspd > 0 ? (approachspd + (metric ? Math.round(info.currentSpeed * 3.6) : Math.round(info.currentSpeed * 2.23694))) : 0;
			rangeDataField.setData(rangeInfo);
			speedDataField.setData(speedInfo);
			passingSpeedRelDataField.setData(approachspd);
			passingSpeedAbsDataField.setData(absolutespd);

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
			} else {
				// only update LAST passing speed to the current absolute speed of the closest car if it wasn't an erroneous "0" speed
				// if this car has passed us on the next reading, it won't be updated so it will be preserved
				if (absolutespd > 0) {
					lastspd = absolutespd;
				}
			}
			// update dist no matter what
			dist = metric?rangeInfo[0]:rangeInfo[0]*3.28084;
			crossedthresh = rangeInfo[0] < THRESH;
			lasttrackcnt=trackcnt;
			countDataField.setData(count);			
			countLapField.setData(lapcount);			
			countSessionField.setData(count);			
		} else {
        	disabled = true;
			// only way to indicate when the radar isn't active is to set the range and speed to bogus (negative) values
			// this prevents us from false negatives in our mapping where we would include "zero cars" on a stretch
			// of road that actually had a bunch of cars, but the radar was off.
			for (var i=0;i<RANGETARGETS;i++) {
			  rangeInfo[i] = -1;  // can keep this one as signed since taking up two bytes anyway ... so -1 still the "bogus" radar disabled value
			  speedInfo[i] = 255;
			}
			approachspd = 0;
			rangeDataField.setData(rangeInfo);
			speedDataField.setData(speedInfo);
			countDataField.setData(count);	
			countLapField.setData(lapcount);			
			countSessionField.setData(count);			
			passingSpeedRelDataField.setData(0); 		
			passingSpeedAbsDataField.setData(0); 		
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
