# mybiketraffic - ConnectIQ app to process Garmin Varia radar data and count vehicles.

v1.0 was a simpledatafield (single data field) app so once you have it loaded onto the garmin it shows up automatically in the list of fields you can select and add to any of the data screen. 
v2.0 is a regular (complex) datafield that works the same way. You must add the datafield to one of your data screens. It also DOES NOT show up in the ConnectIQ screen because those are for full-bodied apps.
v2.0 also introduces settings which you can manipulate using Garmin Connect Mobile and Garmin Express that change what fields are displayed. By default it still only displays the total vehicle count, but you can now also display a lap vehicle count and the approach speed of the nearest vehicle automatically converted to your device units (KPH or MPH). 

The vehicle count algorithm relies on the radar data which already does a pretty good job of separating and splitting up multiple vehicles into multiple objects in the radarinfo array. My counting algorithm looks for a change in the number of "active" vehicles to increase the total vehicle count for the ride.

The total vehicle count and closest passing speed are both stored in the .FIT file in a manner that makes them appear on Garmin Connect. 

Individual records within the .FIT file are also modified by adding two DeveloperFields. The first is all EIGHT of the tracked vehicle ranges. The second is all EIGHT of the tracked vehicle speeds. I was able to squeeze this many into the app by converting the storage from floating point numbers to signed and unsigned half words and bytes. 

NOTE about speeds ... the speeds recorded are RELATIVE speeds. Many people report these speeds as not too accurate (myself included), but that is because the radar itself is far too small and underpowered to get highly accurate speed readings. It's just "ballpark" or "bucket" readings. I still think the data is valuable, but it would be GREAT if Garmin introduced a newer higher accuracy model. 