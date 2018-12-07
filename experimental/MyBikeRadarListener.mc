using Toybox.AntPlus;

class MyBikeRadarListener extends Toybox.AntPlus.BikeRadarListener {

    function initialize() {
        BikeRadarListener.initialize();
    }

    function onBikeRadarUpdate(data) {
        System.println("radar update: " + data);
    }
}