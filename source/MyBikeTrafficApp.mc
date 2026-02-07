using Toybox.Application;

class MyBikeTrafficApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    //! Return the initial view of your application here
    function getInitialView() {
        return [ new MyBikeTrafficView([Application.Properties.getValue("displayTotal"), Application.Properties.getValue("displayLap"), Application.Properties.getValue("displaySpeedRelative"), Application.Properties.getValue("displaySpeedAbsolute"), Application.Properties.getValue("displaySpeedLast"), Application.Properties.getValue("displayClosestDist")], Application.Properties.getValue("autoOrientation"), Application.Properties.getValue("autoLabelSize"), Application.Properties.getValue("autoValueSize")) ];
    }

}