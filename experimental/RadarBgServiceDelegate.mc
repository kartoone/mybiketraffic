using Toybox.AntPlus;
using Toybox.Background;
using Toybox.System as Sys;

// The Service Delegate is the main entry point for background processes
// our onTemporalEvent() method will get run each time our periodic event
// is triggered by the system.

//(:background)
class RadarBgServiceDelegate extends Toybox.System.ServiceDelegate {

    function initialize() {
        Sys.ServiceDelegate.initialize();
    }

	// this eventually should send a webrequest if available so that data can be processed "online"
	// without relying on a user to manually upload .FIT file with sensor data embedded
	// it also should be how we register our bikeradar listener, but apparently that part of the API isn't enabled yet
    function onTemporalEvent() {
    	try {
    		Sys.println("onTemporalEvent");
			// Initialize the AntPlus.BikePowerListener object
//			var listener = new MyBikeRadarListener();
//			Sensor.registerSensorDataListener(listener,{:enableBikeRadar=>true});
        } catch (ex) {
          Sys.println("ex");
        }
    }
}