# mybiketraffic - ConnectIQ app to process Garmin Varia radar data and count vehicles.

The app is a simpledatafield (single data field) app so once you have it loaded onto the garmin it shows up automatically in the list of fields you can select and add to any of the data screen. It DOES NOT show up in the ConnectIQ screen because those are for full-bodied apps.

The vehicle count algorithm relies on the radar data which already does a pretty good job of separating and splitting up multiple vehicles into multiple objects in the radarinfo array. My counting algorithm looks for a change in the number of "active" vehicles to increase the total vehicle count for the ride.

The total vehicle count is stored in the Session data at the end of the .FIT file.

Individual records within the .FIT file are also modified by adding two DeveloperFields. The first is FOUR of the tracked vehicle ranges. The second is FOUR of the tracked vehicle speeds. All EIGHT vehicles are not stored because an app can only store 32bytes of data per record. To store all EIGHT vehicles would require a second data field, which is possible but future work for now. 
