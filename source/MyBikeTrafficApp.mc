using Toybox.Application;

class MyBikeTrafficApp extends Application.AppBase  {

	var count = 0;

    function initialize() {
        AppBase.initialize();
//        Sensor.setEnabledSensors( [Sensor.SENSOR_BIKECADENCE ] );
//    	Sensor.enableSensorEvents( method( :onSensor ) );
    }

	function onBikeRadarUpdate(data) {
		System.println(data);
		count++;
	}

    // onStart() is called on application start up
    function onStart(state) {
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    // Return the initial view of your application here
    function getInitialView() {
        return [ new MyBikeTrafficView() ];
    }

}