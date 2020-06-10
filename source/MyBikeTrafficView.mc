using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.AntPlus;
using Toybox.Sensor;

const BORDER_PAD = 4;
// so there is a little bit of trickery here ... the index in the array corresponds to the font constant 
// ... so no need to reference the array (but probably should) once you have found the index for the font that fits
var fonts = [Graphics.FONT_XTINY,Graphics.FONT_TINY,Graphics.FONT_SMALL,Graphics.FONT_MEDIUM,Graphics.FONT_LARGE,
             Graphics.FONT_NUMBER_MILD,Graphics.FONT_NUMBER_MEDIUM,Graphics.FONT_NUMBER_HOT,Graphics.FONT_NUMBER_THAI_HOT];
             
class MyBikeTrafficView extends WatchUi.DataField {

	hidden var metric = true;
	hidden var vertical = true; // layout (stacked vertical values, or side-by-size horizontal values)
	
	// layout related vars
	// cannot use the strings file when drawing directly onto dc
	hidden var mLabels = ["Total", "Lap", "MPH"];
	hidden var mLabelDebug;
    hidden var mLabelY = 3; 
    hidden var mLabelFont = Graphics.FONT_SMALL;
    hidden var mValueFont = Graphics.FONT_MEDIUM;
	hidden var labelX; // array of X coordinates (only two entries for vertical layout strategy, as many entries as data values being displayed for horizontal layout) 
	hidden var labelY; // array of Y coordinates (only two entries for horizontal layout strategy, as many entries as data values being displayed for horizontal layout)
	hidden var numFields = 0; // this ends up being a count of the array below which is read from the app settings
	hidden var whichFields = [1, 0, 0]; // positional array ... position 0 - total count, position 1 - lap count, position 2 - approach speed ... 0 means don't include, 1 means include ... if ALL THREE are zero then just display total count 
	
	// this is where all the real computational work happens - MyBikeTrafficFitConributions
	hidden var mFitContributor; 
	
	
    function initialize(properties) {
        DataField.initialize();
        
        // get device settings to determine whether metric or statue units
        var sys = System.getDeviceSettings();
        metric = sys.distanceUnits != System.UNIT_STATUTE;
		mLabels[2] = metric ? "KPH" : "MPH";

        // get app settings (passed from the Application class when constructing this view) to determine which fields to display
        whichFields[0] = properties[0] ? 1 : 0;
        whichFields[1] = properties[1] ? 1 : 0;
        whichFields[2] = properties[2] ? 1 : 0;
        
        // for simplicity, let's count how many fields are displayed
        var i;
        for (i=0; i<whichFields.size(); i++) {
          numFields = numFields + whichFields[i];
        }
        
        // if no fields selected, then force the total count to be displayed
        if (numFields == 0) {
        	whichFields[0] = 1;
        	numFields = 1;
        }
        
        mFitContributor = new MyBikeTrafficFitContributions(self, new AntPlus.BikeRadar(null), metric);
    }

    function selectFont(dc, width, height) {
        var testString = "88.88"; //Dummy string to test data width
        var fontIdx;
        var dimensions;
        //Search through fonts from biggest to smallest
        for (fontIdx = (fonts.size() - 1); fontIdx > 0; fontIdx--) {
            dimensions = dc.getTextDimensions(testString, fonts[fontIdx]);
            if ((dimensions[0] <= width) && (dimensions[1] <= height)) {
                //If this font fits, it is the biggest one that does
                break;
            }
        } 
        return fontIdx;
    }

    // Two layout strategies
    // 	1. displaying three fields, need to stack
    // 	2. displaying one or two fields, can go side-by-side, or (three fields if wide-layout)
    function onLayout(dc) {
        View.setLayout(Rez.Layouts.MainLayout(dc));
        var labelView = View.findDrawableById("label");
        var width = dc.getWidth();
        var height = dc.getHeight();
        var top = mLabelY + BORDER_PAD;
        mLabelDebug = width + " " + height + " " + top;
        
        // lots of horizontal room for number of fields we are displaying ... more room if we do horizontal layout
		if ((numFields < 3 || width > 180) && height<150) {
			vertical = false;
			var vroom = height - top;
			var vfontmax = Math.round(vroom*(2.0/3.0)); // allow the value to take up 2/3rds of vertical space
			var hfontmax = Math.round(width/numFields);
			mValueFont = selectFont(dc, hfontmax, vfontmax);
			labelY = [ top, top + (vroom*(1.0/3.0)) ];
			// silly, but easiest way to do this is to simply handle all three scenarios (1 field, 2 field, 3 fields) manually
			switch (numFields) {
				case 1: labelX = [ 0.5*width ]; break;
				case 2: labelX = [ 0.33*width, 0.67*width]; break;
				case 3: labelX = [ 0.2*width, 0.55*width, 0.8*width]; break;
				default: break;
			}
        } else {
	        // lots of vertical room, let's do vertical layout 
        	var vroom = height - top;
        	var vfontmax = Math.round(vroom/numFields);
        	var hfontmax = Math.round(width*(2.0/3.0));
        	labelX = [ Math.round(width*(1.0/3.0)) - 3, Math.round(width*(1.0/3.0)) + 3 ];
        	mValueFont = selectFont(dc, hfontmax, vfontmax);
        	var dimensions = dc.getTextDimensions("88.88", mValueFont);
        	// dimensions[1] will have the height we need to space things out by
        	labelY = [ top, top + dimensions[1], top + dimensions[1]*2 ];
			// silly, but easiest way to do this is to simply handle all three scenarios (1 field, 2 field, 3 fields) manually
			switch (numFields) {
				case 1: labelY = [ top ]; break;
				case 2: labelY = [ top, top + dimensions[1]]; break;
				case 3: labelY = [ top, top + dimensions[1], top + dimensions[1]*2 ]; break;
				default: break;
			}
        	vertical = true;
        }
        
        // fudge code to make sure that the label font is NEVER bigger than (or equal to) the value font ... unless they both end up being XTINY (0)
        while (mLabelFont >= mValueFont && mLabelFont>0) {
        	mLabelFont = mLabelFont - 1;
       	}
        
        labelView.setText(Rez.Strings.label);
//        labelView.setText(mLabelDebug);
        return true;
    }

    function compute(info) {
        mFitContributor.compute(info);
    }

    // Display the value you computed here. This will be called
    // once a second when the data field is visible.
    function onUpdate(dc) {
    	// before we do anything else
    	// let's prep the display strings
    	var countstr;
    	var lapstr;
    	var spdstr;
    	
    	if (mFitContributor.disabled) {
    		countstr = "--";
    		lapstr = "--";
    		spdstr = "--";
    	} else {
    		countstr = mFitContributor.count.format("%d");
    		lapstr = mFitContributor.lapcount.format("%d");
    		spdstr = mFitContributor.approachspd.format("%d");
		}    	

        // Set the colors
        View.findDrawableById("Background").setColor(getBackgroundColor());
        var bgColor = getBackgroundColor();
        var fgColor = Graphics.COLOR_WHITE;
        var lblColor = Graphics.COLOR_ORANGE;
        if (bgColor == Graphics.COLOR_WHITE) {
            fgColor = Graphics.COLOR_BLACK;
            lblColor = Graphics.COLOR_LT_GRAY;
        }
        // The following two lines are probably unnecessary b/c View.onUpdate(dc) does this ... but JUST IN CASE...
        dc.setColor(fgColor, bgColor);
        dc.clear();

        // Call parent's onUpdate(dc) to redraw the layout ... the only thing FIXED in the layout is the VC symbol in upper right
        // This call below redraws that label so we don't have to redraw it ... everything else we need to position and draw ourselves
        View.onUpdate(dc);

		// Now let's handle the direct drawing of text ... do the labels first
		if (vertical) {
	    	// labels first
	    	dc.setColor(lblColor, Graphics.COLOR_TRANSPARENT);
	    	var i;
	    	var labeli = 0;
	    	for (i=0; i<whichFields.size(); i++) {
	    	  if (whichFields[i] == 1) {
	    	    dc.drawText(labelX[0], labelY[labeli], mLabelFont, mLabels[i], Graphics.TEXT_JUSTIFY_RIGHT);
	    	    labeli = labeli + 1;
	    	  }
	    	}
	        
	        // Now let's draw the values
	        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
	        var valuei = 0;
	        for (i=0; i<whichFields.size(); i++) {
	    	  if (whichFields[i] == 1) {
	    	  	var valstr;
	    	  	switch(i) {
	    	  		case 0: valstr = countstr; break;
	    	  		case 1: valstr = lapstr; break;
	    	  		case 2: valstr = spdstr; break;
	    	  		default: valstr = countstr; break;
	    	  	}
	    	    dc.drawText(labelX[1], labelY[valuei], mValueFont, valstr, Graphics.TEXT_JUSTIFY_LEFT);
	    	    valuei = valuei + 1;
	    	  }
	    	}
	    } else {
	    	// labels first
	    	dc.setColor(lblColor, Graphics.COLOR_TRANSPARENT);
	    	var i;
	    	var labeli = 0;
	    	for (i=0; i<whichFields.size(); i++) {
	    	  if (whichFields[i] == 1) {
	    	    dc.drawText(labelX[labeli], labelY[0], mLabelFont, mLabels[i], Graphics.TEXT_JUSTIFY_CENTER);
	    	    labeli = labeli + 1;
	    	  }
	    	}
	        
	        // Now let's draw the values
	        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
	        var valuei = 0;
	        for (i=0; i<whichFields.size(); i++) {
	    	  if (whichFields[i] == 1) {
	    	  	var valstr;
	    	  	switch(i) {
	    	  		case 0: valstr = countstr; break;
	    	  		case 1: valstr = lapstr; break;
	    	  		case 2: valstr = spdstr; break;
	    	  		default: valstr = countstr; break;
	    	  	}
	    	    dc.drawText(labelX[valuei], labelY[1], mValueFont, valstr, Graphics.TEXT_JUSTIFY_CENTER);
	    	    valuei = valuei + 1;
	    	  }
	    	}
	    }
    }
    
    // activity has ended
    // handle resetting count to 0 after activity has ended
    function onTimerReset() {
    	mFitContributor.onTimerReset();
    }
    
    // simply reset the lapcount ... lap data already written out once per second (per documentation) overwriting previous lap message ... this is the way it's supposed to work!
    function onTimerLap() {
    	mFitContributor.onTimerLap();
    }
    

}
