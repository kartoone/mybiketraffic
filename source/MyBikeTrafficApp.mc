using Toybox.Application;

class MyBikeTrafficApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    //! Return the initial view of your application here
    function getInitialView() {
        var displayPositions = [
            Application.Properties.getValue("displayTotalPosition"),
            Application.Properties.getValue("displayLapPosition"),
            Application.Properties.getValue("displaySpeedRelativePosition"),
            Application.Properties.getValue("displaySpeedAbsolutePosition"),
            Application.Properties.getValue("displaySpeedLastPosition"),
            Application.Properties.getValue("displayClosestDistPosition")
        ];
        var view = new MyBikeTrafficView(displayPositions, Application.Properties.getValue("displayDebugStatus"), Application.Properties.getValue("autoOrientation"), Application.Properties.getValue("autoLabelSize"), Application.Properties.getValue("autoValueSize"), Application.Properties.getValue("connectionBehaviorMode"));
        return [ view, new MyBikeTrafficViewDelegate(view) ];
    }

}