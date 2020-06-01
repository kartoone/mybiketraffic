# mybiketraffic - ConnectIQ app to process Garmin Varia radar data and count vehicles.

The app is a simpledatafield (single data field) app so once you have it loaded onto the garmin it shows up automatically in the list of fields you can select and add to any of the data screen. It DOES NOT show up in the ConnectIQ screen because those are for full-bodied apps.

The vehicle count algorithm relies on the radar data which already does a pretty good job of separating and splitting up multiple vehicles into multiple objects in the radarinfo array. My counting algorithm looks for a change in the number of "active" vehicles to increase the total vehicle count for the ride.

The total vehicle count and closest passing speed are both stored in the .FIT file in a manner that makes them appear on Garmin Connect. 

Individual records within the .FIT file are also modified by adding two DeveloperFields. The first is all EIGHT of the tracked vehicle ranges. The second is all EIGHT of the tracked vehicle speeds. I was able to squeeze this many into the app by converting the storage from floating point numbers to signed and unsigned half words and bytes. 
