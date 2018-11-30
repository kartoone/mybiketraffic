using Toybox.WatchUi;
using Toybox.AntPlus;
using Toybox.Sensor;
using Toybox.Position;

class MyBikeTrafficView extends WatchUi.SimpleDataField {

	var listener;
	var bikeRadar; 
	var count=0;
	
    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();
        label = "VehicleCount";
		listener = new MyBikeRadarListener();
		// Initialize the AntPlus.BikePower object with a listener
		bikeRadar = new AntPlus.BikeRadar(listener);
    }

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info) { 
//    	System.println("computing");
        var radarInfo = bikeRadar.getRadarInfo();
        if (radarInfo) {
        	for(var i=0;i<radarInfo.size();i++) {
        	  if(radarInfo[i].threat!=0) {
        	  	System.print(i+": "+Time.now().value().toString()+" ");
        	  	count++;
        	  	if (info.currentSpeed!=null) {
        	  		System.print(info.currentSpeed + " ");
        	  	} else {
        	  		System.print("n/a ");
        	    }
        	  	if (info.currentLocation!= null) {
        	  	    var myLocation = info.currentLocation.toDegrees();
        	  		var lat = myLocation[0];
        	  		var lng = myLocation[1];
        	  		System.print(lat + " " + lng); 
        	  	} else {
        	  		System.print("n/a");
        	    }
        	  	System.print(' ');  
				System.print(radarInfo[i].range);
				System.print(' ');
				System.print(radarInfo[i].speed);
				System.print(' ');
				System.print(radarInfo[i].threat);
				System.print(' ');
				System.print(radarInfo[i].threatSide);
				System.println(' ');
		 	  }		 
			}
	        return count;
		} else {
			return "--";
		}		
    }
 
}