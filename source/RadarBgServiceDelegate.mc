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

    function onTemporalEvent() {
    	try {
			// Initialize the AntPlus.BikePowerListener object
			var listener = new MyBikeRadarListener();
			// Initialize the AntPlus.BikePower object with a listener
			var bikeRadar = new AntPlus.BikeRadar(listener);
			var radarInfo = bikeRadar.getRadarInfo();
        } catch (ex) {
          Sys.println("ex");
        }
    }
}