using Toybox.Application;

class MyBikeTrafficApp extends Application.AppBase  {

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
//	    if(Toybox.System has :ServiceDelegate) {
//            Background.registerForTemporalEvent(new Time.Duration(60*5));
//        } 
        return [ new MyBikeTrafficView() ];
    }

//	function onBackgroundData(data) {
//        count++;
//    }

//    function getServiceDelegate(){
//        return [new RadarBgServiceDelegate()];
//    }        
}