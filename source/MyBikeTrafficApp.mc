using Toybox.Application;
using Toybox.Position;

class MyBikeTrafficApp extends Application.AppBase  {

    var radarview;
    var speedview;
	
    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    // Return the initial view of your application here
    function getInitialView() {
		radarview = new MyBikeTrafficView();
        return [ radarview ];
    }

}