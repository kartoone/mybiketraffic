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
	
	// datafield attributes and constants for custom data written into FIT files
	var rangeDataField;
//	var speedDataField;
	var threatDataField;
//	var threatsideDataField; 
	
	const BT_RANGE_FIELD_ID = 0; // range floats
	const BT_THREAT_FIELD_ID = 1; // threat level bytes, 0-no threat,1-approaching,2-fast approaching
//	const BT_SPEED_FIELD_ID = 2;  speed floats
//	const BT_THREATSIDE_FIELD_ID = 3; 	threat side 0-left, 1-right
	
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
            FitContributor.DATA_TYPE_FLOAT,
            {:count=>6,:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
		threatDataField = createField(
            "radar_threats",
            BT_THREAT_FIELD_ID,
            FitContributor.DATA_TYPE_UINT8,
            {:count=>6,:mesgType=>FitContributor.MESG_TYPE_RECORD}
        );
// not enough room to store this data ... field limited to 32 bytes of data per message ... 6*4 + 6*1 = 30bytes
//		speedDataField = createField(
//            "radar_speeds",
//            BT_SPEED_FIELD_ID,
//            FitContributor.DATA_TYPE_FLOAT,
//            {:count=>8,:mesgType=>FitContributor.MESG_TYPE_RECORD}
//        );
//		threatsideDataField = createField(
//            "radar_threatsides",
//            BT_THREATSIDE_FIELD_ID,
//            FitContributor.DATA_TYPE_UINT8,
//            {:count=>8,:mesgType=>FitContributor.MESG_TYPE_RECORD}
//        );
    }
    
    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    // Radar algorithm
    //   encode each array of up to 8 targets into as small a string as possible
    //   b/c each field is limited to 32bytes
    function compute(info) { 
        var radarInfo = bikeRadar.getRadarInfo();
        if (radarInfo) {
			var rangeInfo = new [6];
			var threatInfo = new [rangeInfo.size()];
			for (var i=0;i<rangeInfo.size();i++) {
			  rangeInfo[i] = radarInfo[i].range;
			  threatInfo[i] = radarInfo[i].threat;
			}
			rangeDataField.setData(rangeInfo);
			threatDataField.setData(threatInfo);

        	for(var i=0;i<radarInfo.size();i++) {
        	  if(radarInfo[i].threat!=0) {
        	  	count++;
//        	  	if (info.currentSpeed!=null) {
//        	  		System.print(info.currentSpeed + " ");
//        	  	} else {
//        	  		System.print("n/a ");
//        	    }
//        	  	if (info.currentLocation!= null) {
//        	  	    var myLocation = info.currentLocation.toDegrees();
//        	  		var lat = myLocation[0];
//        	  		var lng = myLocation[1];
//        	  		System.print(lat + " " + lng); 
//        	  	} else {
//        	  		System.print("n/a");
//        	    } 
		 	  }		 
			}
	        return count;
		} else {
			return "--";
		}		
    }
 
}