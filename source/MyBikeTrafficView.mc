using Toybox.WatchUi;
using Toybox.AntPlus;

class MyBikeTrafficView extends WatchUi.SimpleDataField {

	var listener;
	var bikeRadar;
	var radarInfo;
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
    	System.println("computing");
        radarInfo = bikeRadar.getRadarInfo();
        if (radarInfo) {
        	for(var i=0;i<radarInfo.size();i++) {
				System.print(radarInfo[i].range);
				System.print(' ');
			}
		}
        // See Activity.Info in the documentation for available information.
        return count;
    }

}