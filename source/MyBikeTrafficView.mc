using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Time;

// so there is a little bit of trickery here ... the index in the array corresponds to the font constant 
// ... so no need to reference the array (but probably should) once you have found the index for the font that fits
var fonts as Lang.Array<Graphics.FontType> = [Graphics.FONT_XTINY,Graphics.FONT_TINY,Graphics.FONT_SMALL,Graphics.FONT_MEDIUM,Graphics.FONT_LARGE,
             Graphics.FONT_NUMBER_MILD,Graphics.FONT_NUMBER_MEDIUM,Graphics.FONT_NUMBER_HOT,Graphics.FONT_NUMBER_THAI_HOT]; 
             
class MyBikeTrafficView extends WatchUi.DataField {

	hidden var metric = true;	
	hidden var vertical = true; // layout (stacked vertical values, or side-by-size horizontal values)
	hidden var autoOrientation = -1; // -1 mean auto, 0 means force horizontal, 1 means force vertical 
	hidden var autoLabelSize = -2; // -2 means auto with max of tiny, -1 means off (i.e., no label), 0 means xtiny, 1 means tiny, etc...
	hidden var autoValueSize = -1; // -1 means auto with no max, 0 means xtiny, 1 means tiny, etc...
	hidden var showDebugStatus = true;
	hidden var mConnectionBehaviorMode = 1;
	hidden var mStatusFont = Graphics.FONT_TINY;
	hidden var mPendingResetTap = false;
	hidden var mPendingResetTapDeadline as Lang.Number or Null;
	const RESET_CONFIRM_SECONDS = 1;

	// layout related vars
	// cannot use the strings file when drawing directly onto dc
	hidden var mLabels as Lang.Array<Lang.String>?; // array of labels to display ... this is set based on how many fields are displayed
	hidden var mLabelSet = 1;
    hidden var mLabelFont = Graphics.FONT_TINY;
    hidden var mValueFont = Graphics.FONT_MEDIUM;
    hidden var mUnitsFont = Graphics.FONT_XTINY; // always use tiny font for kph/mph
	hidden var fh;
	hidden var labelX as Lang.Array<Lang.Float or Lang.Number>?; // array of X coordinates (only two entries for vertical layout strategy, as many entries as data values being displayed for horizontal layout) 
	hidden var labelY as Lang.Array<Lang.Float or Lang.Number>?; // array of Y coordinates (only two entries for horizontal layout strategy, as many entries as data values being displayed for horizontal layout)
	hidden var numFields = 0; // number of fields actively rendered after applying the ordered settings
	const MAX_DISPLAY_SLOTS = 6; // max number of fields shown at once, fixed by screen space (independent of how many field types are configurable)
	hidden var fieldPositions as Lang.Array<Lang.Number> = [1, 0, 0, 2, 0, 0, 0]; // position 0 - total count, 1 - lap count, 2 - approach speed, 3 - absolute vehicle speed, 4 - last vehicle speed, 5 - closest vehicle distance, 6 - speed trend. 0 means hidden.
	hidden var displayedFields as Lang.Array<Lang.Number> = [0]; // ordered list of field ids to render
	hidden var mCachedValueNumbers as Lang.Array<Lang.Number> = [-1, -1, -1, -1, -1, -1, -1];
	hidden var mCachedValueStrings as Lang.Array<Lang.String> = ["", "", "", "", "", "", ""];
	hidden var mCachedValueWidths as Lang.Array<Lang.Number> = [0, 0, 0, 0, 0, 0, 0];
	hidden var mCachedValueFonts as Lang.Array<Lang.Number> = [-1, -1, -1, -1, -1, -1, -1];
	
	hidden var testString = "888" as Lang.String;   // start out using small text string for font layout ... change this as the counts get larger
    hidden var totalDigits = 2; 	// this is the total digit count for both the vehicle count field and lap count field ... assume 4
    hidden var needLayout = false;  // flag to set if we need to manually re-layout b/c count has increased enough to increase number of digits
	
	// this is where all the real computational work happens - MyBikeTrafficFitConributions
	hidden var mFitContributor as MyBikeTrafficFitContributions or Null;
	const FIELD_TOTAL = 0;
	const FIELD_LAP = 1;
	const FIELD_SPEED_RELATIVE = 2;
	const FIELD_SPEED_ABSOLUTE = 3;
	const FIELD_SPEED_LAST = 4;
	const FIELD_DISTANCE_CLOSEST = 5;
	const FIELD_SPEED_TREND = 6;
	
	function initialize(displayPositions as Lang.Array, debugStatus as Lang.Boolean or Null, autoOrientation as Lang.Number, autoLabelSize as Lang.Number, autoValueSize as Lang.Number, connectionBehaviorMode as Lang.Number or Null) {
        DataField.initialize();
        
        // get device settings to determine whether metric or statue units
        var sys = System.getDeviceSettings();
        metric = sys.distanceUnits != System.UNIT_STATUTE;

		// get app settings (passed from the Application class when constructing this view) to determine which fields to display and in what order
		for (var i = 0; i < fieldPositions.size() && i < displayPositions.size(); i++) {
			if (displayPositions[i] != null) {
				fieldPositions[i] = displayPositions[i];
			}
		}
		if (debugStatus != null) {
			showDebugStatus = debugStatus;
		}
		if (connectionBehaviorMode != null) {
			mConnectionBehaviorMode = connectionBehaviorMode;
		}
		// Preserve direct-on-device test overrides when settings are not reachable.
		//fieldPositions = [1, 2, 0, 3, 4, 5];
		//showDebugStatus = true;
		//mConnectionBehaviorMode = 1; // 0 - always 820, 1 - never 820, 2 - auto-detect
		_rebuildDisplayedFields();

		// orientation and font size settings
		self.autoOrientation = autoOrientation;
		self.autoLabelSize = autoLabelSize;
		self.autoValueSize = autoValueSize;

		// if either of the font sizes are NOT set to auto, then use the specified font size ... otherwise will determine font size dynamically in onLayout() based on how many fields are being displayed and how much room we have to display them
		if (autoLabelSize >= 0) {
			mLabelFont = fonts[autoLabelSize];
		}
		if (autoValueSize >= 0) {
			mValueFont = fonts[autoValueSize];
		}

		// setup the labels based on how many fields are displayed
        switch (numFields) {
        	case 1:
				mLabelSet = 1;
				break;        		
        	case 2:
				mLabelSet = 2;
				break;        		
        	case 3:
        	case 4:
			case 5:
			case 6:
				mLabelSet = 3;
				break;
		}        		

		mLabels = null;
		mFitContributor = null;
    }

	hidden function _rebuildDisplayedFields() as Void {
		displayedFields = [] as Lang.Array<Lang.Number>;

		for (var slot = 1; slot <= MAX_DISPLAY_SLOTS; slot++) {
			for (var fieldIndex = 0; fieldIndex < fieldPositions.size(); fieldIndex++) {
				if (fieldPositions[fieldIndex] == slot) {
					displayedFields.add(fieldIndex);
				}
			}
		}

		for (var fieldIndex = 0; fieldIndex < fieldPositions.size(); fieldIndex++) {
			if (fieldPositions[fieldIndex] > MAX_DISPLAY_SLOTS) {
				displayedFields.add(fieldIndex);
			}
		}

		if (displayedFields.size() == 0) {
			displayedFields.add(FIELD_TOTAL);
		}

		numFields = displayedFields.size();
	}

	hidden function _loadLabels(labelSet as Lang.Number) as Lang.Array<Lang.String> {
		switch (labelSet) {
			case 1:
				return [
					WatchUi.loadResource($.Rez.Strings.ml1_vc),
					WatchUi.loadResource($.Rez.Strings.ml1_lvc),
					WatchUi.loadResource($.Rez.Strings.ml1_rspd),
					WatchUi.loadResource($.Rez.Strings.ml1_aspd),
					WatchUi.loadResource($.Rez.Strings.ml1_lspd),
					WatchUi.loadResource($.Rez.Strings.ml1_dist),
					WatchUi.loadResource($.Rez.Strings.ml1_trend)
				];
			case 2:
				return [
					WatchUi.loadResource($.Rez.Strings.ml2_vc),
					WatchUi.loadResource($.Rez.Strings.ml2_lvc),
					WatchUi.loadResource($.Rez.Strings.ml2_rspd),
					WatchUi.loadResource($.Rez.Strings.ml2_aspd),
					WatchUi.loadResource($.Rez.Strings.ml2_lspd),
					WatchUi.loadResource($.Rez.Strings.ml2_dist),
					WatchUi.loadResource($.Rez.Strings.ml2_trend)
				];
		}

		return [
			WatchUi.loadResource($.Rez.Strings.ml3_vc),
			WatchUi.loadResource($.Rez.Strings.ml3_lvc),
			WatchUi.loadResource($.Rez.Strings.ml3_rspd),
			WatchUi.loadResource($.Rez.Strings.ml3_aspd),
			WatchUi.loadResource($.Rez.Strings.ml3_lspd),
			WatchUi.loadResource($.Rez.Strings.ml3_dist),
			WatchUi.loadResource($.Rez.Strings.ml3_trend)
		];
	}

	hidden function _ensureFitContributor() as MyBikeTrafficFitContributions {
		if (mFitContributor == null) {
			mFitContributor = new MyBikeTrafficFitContributions(self, metric, mConnectionBehaviorMode);
		}
		return mFitContributor;
	}

	hidden function _ensureLabels() as Lang.Array<Lang.String> {
		if (mLabels == null) {
			mLabels = _loadLabels(mLabelSet);
		}
		return mLabels;
	}

	hidden function _getFieldValue(fieldIndex as Lang.Number, countstr as Lang.String, lapstr as Lang.String, spdstr as Lang.String, absstr as Lang.String, laststr as Lang.String, diststr as Lang.String, trendstr as Lang.String) as Lang.String {
		switch (fieldIndex) {
			case FIELD_TOTAL: return countstr;
			case FIELD_LAP: return lapstr;
			case FIELD_SPEED_RELATIVE: return spdstr;
			case FIELD_SPEED_ABSOLUTE: return absstr;
			case FIELD_SPEED_LAST: return laststr;
			case FIELD_DISTANCE_CLOSEST: return diststr;
			case FIELD_SPEED_TREND: return trendstr;
		}

		return countstr;
	}

	hidden function _showsSpeedUnits(fieldIndex as Lang.Number) as Lang.Boolean {
		return fieldIndex == FIELD_SPEED_RELATIVE || fieldIndex == FIELD_SPEED_ABSOLUTE || fieldIndex == FIELD_SPEED_LAST;
	}

	hidden function _showsDistanceUnits(fieldIndex as Lang.Number) as Lang.Boolean {
		return fieldIndex == FIELD_DISTANCE_CLOSEST;
	}

	hidden function _getCachedUnavailableValue(fieldIndex as Lang.Number) as Lang.String {
		if (mCachedValueNumbers[fieldIndex] != -1 || mCachedValueStrings[fieldIndex] != "--") {
			mCachedValueNumbers[fieldIndex] = -1;
			mCachedValueStrings[fieldIndex] = "--";
			mCachedValueFonts[fieldIndex] = -1;
		}
		return mCachedValueStrings[fieldIndex];
	}

	hidden function _getCachedFormattedValue(fieldIndex as Lang.Number, value as Lang.Number) as Lang.String {
		if (mCachedValueNumbers[fieldIndex] != value || mCachedValueStrings[fieldIndex] == "" || mCachedValueStrings[fieldIndex] == "--") {
			mCachedValueNumbers[fieldIndex] = value;
			mCachedValueStrings[fieldIndex] = value.format("%d");
			mCachedValueFonts[fieldIndex] = -1;
		}
		return mCachedValueStrings[fieldIndex];
	}

	hidden function _getCachedValueWidth(dc, fieldIndex as Lang.Number, valueString as Lang.String) as Lang.Number {
		if (mCachedValueFonts[fieldIndex] != mValueFont || mCachedValueStrings[fieldIndex] != valueString) {
			mCachedValueStrings[fieldIndex] = valueString;
			mCachedValueFonts[fieldIndex] = mValueFont;
			mCachedValueWidths[fieldIndex] = (dc.getTextDimensions(valueString, mValueFont) as Lang.Array<Lang.Numeric>)[0];
		}
		return mCachedValueWidths[fieldIndex];
	}

	hidden function _getCachedStringValue(fieldIndex as Lang.Number, value as Lang.String) as Lang.String {
		if (mCachedValueStrings[fieldIndex] != value) {
			mCachedValueNumbers[fieldIndex] = -1;
			mCachedValueStrings[fieldIndex] = value;
			mCachedValueFonts[fieldIndex] = -1;
		}
		return mCachedValueStrings[fieldIndex];
	}

	hidden function _trendSymbol(trendValue as Lang.Number) as Lang.String {
		if (trendValue == 1) {
			return "+";
		}
		if (trendValue == -1) {
			return "-";
		}
		return "=";
	}
    
    function countDigits(num) {
      	return num<1000?num<100?num<10?1:2:num<1000?3:4:5;
    }

	hidden function _getStatusReserveHeight(dc) as Lang.Number {
		if (!showDebugStatus && !mPendingResetTap) {
			return 0;
		}
		return dc.getFontHeight(mStatusFont) + 2;
	}

	hidden function _nowResetTapTime() as Lang.Number or Null {
		try {
			return Time.now().value();
		} catch(e) {}
		return null;
	}

	hidden function _clearPendingResetTap() as Void {
		mPendingResetTap = false;
		mPendingResetTapDeadline = null;
	}

	hidden function _tickPendingResetTap() as Void {
		if (!mPendingResetTap) {
			return;
		}

		var now = _nowResetTapTime();
		if (now == null || mPendingResetTapDeadline == null) {
			_clearPendingResetTap();
			needLayout = true;
			return;
		}

		if (now >= mPendingResetTapDeadline) {
			_clearPendingResetTap();
			needLayout = true;
		}
	}

	function handleResetTap() as Void {
		if (!mPendingResetTap) {
			var now = _nowResetTapTime();
			if (now == null) {
				return;
			}
			mPendingResetTap = true;
			mPendingResetTapDeadline = now + RESET_CONFIRM_SECONDS;
			needLayout = true;
			return;
		}

		_clearPendingResetTap();
		needLayout = true;
		if (mFitContributor != null) {
			mFitContributor.bikeRadar.requestRawWaitReset();
		}
	}

    function selectFont(dc, width, height) {
        //var testString = "88.88"; //Dummy string to test data width
        var fontIdx;
        //Search through fonts from biggest to smallest
        for (fontIdx = (fonts.size() - 1); fontIdx > 0; fontIdx--) {
            var dimensions = dc.getTextDimensions(testString, fonts[fontIdx]) as Lang.Array<Lang.Numeric>;
            if ((dimensions[0] <= width) && (dimensions[1] <= height-2)) {
                //If this font fits, it is the biggest one that does
                break;
            }
        } 
		fh = dc.getFontHeight(mValueFont);	    	    	
        return fontIdx;
    }

    // Two layout strategies
    // 	1. displaying three fields, need to stack
    // 	2. displaying one or two fields, can go side-by-side, or (three fields if wide-layout)
    function onLayout(dc) {
        var width = dc.getWidth();
		var height = dc.getHeight() - _getStatusReserveHeight(dc);
        var top = 5;
        
        // lots of horizontal room for number of fields we are displaying ... more room if we do horizontal layout
		// -1 for auto orientation, 1 for force vertical, 0 for force horizontal 
		if (autoOrientation == 0 || autoOrientation == -1 && (numFields < 3 || width > 180)) {
			vertical = false;
			var vroom = height - top;
			var labelHeight = autoLabelSize != -1 ? dc.getFontHeight(mLabelFont) : top;
			var vfontmax = vroom - labelHeight;
			var hfontmax = Math.round(width/numFields);
			if (autoValueSize == -1) {
				mValueFont = selectFont(dc, hfontmax, vfontmax);
			} else {
				fh = dc.getFontHeight(mValueFont);
			}
			labelY = [ top, labelHeight ];
			// silly, but easiest way to do this is to simply handle all scenarios (1 field, 2 field, 3 fields, etc...) manually
			switch (numFields) {
				case 1: labelX = [ 0.5*width ]; break;
				case 2: labelX = [ 0.33*width, 0.67*width]; break;
				case 3: labelX = [ 0.25*width, 0.55*width, 0.8*width]; break;
				case 4: labelX = [ 0.2*width, 0.43*width, 0.63*width, 0.84*width]; break;
				case 5: labelX = [ 0.12*width, 0.27*width, 0.43*width, 0.59*width, 0.84*width]; break;
				case 6: labelX = [ 0.08*width, 0.22*width, 0.36*width, 0.50*width, 0.64*width, 0.88*width]; break;
				default: break;
			}
        } else {
	        // lots of vertical room, let's do vertical layout ... OR auto-orientation MUST have been set to 1 to get here, which means force vertical 
        	var vroom = height - top;
        	var vfontmax = Math.round(vroom/numFields);
			var nonlabelfract = autoLabelSize!=-1 ? 2.0/3.0 : 0.95; 
        	var hfontmax = Math.round(width*nonlabelfract);
        	labelX = autoLabelSize != -1 ?[ Math.round(width*(1.15/3.0)) - 3, Math.round(width*(1.15/3.0)) + 3 ] : [0, 3];
			if (autoValueSize == -1) {
				mValueFont = selectFont(dc, hfontmax, vfontmax);
			} else {
				fh = dc.getFontHeight(mValueFont);
			}
	        	var valueHeight = dc.getFontHeight(mValueFont); 
	        	// valueHeight will have the height we need to space things out by
			// silly, but easiest way to do this is to simply handle all scenarios (1 field, 2 field, 3 fields, etc...) manually
			switch (numFields) {
				case 1: labelY = [ top ]; break;
				case 2: labelY = [ top, top + valueHeight]; break;
				case 3: labelY = [ top, top + valueHeight, top + valueHeight*2 ]; break;
				case 4: labelY = [ top, top + valueHeight, top + valueHeight*2, top + valueHeight*3 ]; break;
				case 5: labelY = [ top, top + valueHeight, top + valueHeight*2, top + valueHeight*3, top+valueHeight*4 ]; break;
				case 6: labelY = [ top, top + valueHeight, top + valueHeight*2, top + valueHeight*3, top+valueHeight*4, top+valueHeight*5 ]; break;
				default: break;
			}
        	vertical = true;
        }
        
        // fudge code to make sure that the label font is NEVER bigger than (or equal to) the value font ... unless they both end up being XTINY (0)
		// but only do this if we haven't turned labels off
        while (autoLabelSize != -1 && mLabelFont >= mValueFont && mLabelFont>0) {
        	mLabelFont = mLabelFont - 1;
       	}
        
    }

    function compute(info) {
		_tickPendingResetTap();
		if (mFitContributor == null && info.timerState != 3) {
			return;
		}

		var fitContributor = _ensureFitContributor();
		fitContributor.compute(info);
        // see if we need to update fonts

		var newtotalDigits = 0;
		if (vertical) {
			// only need to count the likely widest field
			newtotalDigits = countDigits(fitContributor.count);
		} else {
			// need to count all fields ... roughly estimate based on likely widest field
	        	newtotalDigits = countDigits(fitContributor.count*numFields);
		}
        if (newtotalDigits > totalDigits) {
			while (totalDigits < newtotalDigits) {
        		testString = testString + "8"; // concatenate a digit onto the test string
				totalDigits = totalDigits + 1;
			}
        	needLayout = true;
        }
    }

    // Display the value you computed here. This will be called
    // once a second when the data field is visible.
    function onUpdate(dc) {
    	// before we do anything else
    	// let's prep the display strings
    	var countstr;
    	var lapstr;
    	var spdstr;
    	var absstr;
		var laststr;
		var diststr;
		var trendstr;
    	var unitsstr;
		var dunitsstr;
		var fitContributor = mFitContributor;
		var labels = autoLabelSize != -1 ? _ensureLabels() : null;
    	
	    if (fitContributor == null || fitContributor.disabled) {
	    	countstr = _getCachedUnavailableValue(FIELD_TOTAL);
	    	lapstr = _getCachedUnavailableValue(FIELD_LAP);
	    	spdstr = _getCachedUnavailableValue(FIELD_SPEED_RELATIVE);
	    	absstr = _getCachedUnavailableValue(FIELD_SPEED_ABSOLUTE);
			laststr = _getCachedUnavailableValue(FIELD_SPEED_LAST);
			diststr = _getCachedUnavailableValue(FIELD_DISTANCE_CLOSEST);
			trendstr = _getCachedUnavailableValue(FIELD_SPEED_TREND);
    		unitsstr = " "; 
			dunitsstr = " ";
    	} else {
	    	countstr = _getCachedFormattedValue(FIELD_TOTAL, fitContributor.count);
	    	lapstr = _getCachedFormattedValue(FIELD_LAP, fitContributor.lapcount);
	    	spdstr = _getCachedFormattedValue(FIELD_SPEED_RELATIVE, fitContributor.approachspd);
	    	absstr = _getCachedFormattedValue(FIELD_SPEED_ABSOLUTE, fitContributor.absolutespd);
			laststr = _getCachedFormattedValue(FIELD_SPEED_LAST, fitContributor.lastspd);
			diststr = _getCachedFormattedValue(FIELD_DISTANCE_CLOSEST, fitContributor.dist);
			trendstr = _getCachedStringValue(FIELD_SPEED_TREND, _trendSymbol(fitContributor.speedTrend));
    		unitsstr = metric?"kph":"mph"; 
    		dunitsstr = metric?"m":"ft"; 
		}
		
		// see if we need to redo the layout (b/c font size needs to change)
		if (needLayout) {
			needLayout = false;
			onLayout(dc);
		}    	

        // Set the colors
        var bgColor = getBackgroundColor();
        var fgColor = Graphics.COLOR_WHITE;
        if (bgColor == Graphics.COLOR_WHITE) {
            fgColor = Graphics.COLOR_BLACK;
        }
        var lblColor = fgColor;
        // The following two lines are probably unnecessary b/c View.onUpdate(dc) does this ... but JUST IN CASE...
        dc.setColor(fgColor, bgColor);
        dc.clear();
        
        // flag var for displaying units at appropriate place(s)
        var speedflag = false;
		var distflag = false;

		// Now let's handle the direct drawing of text ... do the labels first
		if (vertical) {
	    	// labels first
			if (autoLabelSize != -1) {
	    		dc.setColor(lblColor, Graphics.COLOR_TRANSPARENT);
	    		for (var labeli = 0; labeli < displayedFields.size(); labeli++) {
	    			var fieldIndex = displayedFields[labeli];
	    			dc.drawText(labelX[0], labelY[labeli], mLabelFont, labels[fieldIndex], Graphics.TEXT_JUSTIFY_RIGHT);
	    		}
			}
	        
	        // Now let's draw the values
	        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
	    	var valstr = 0;
	        for (var valuei = 0; valuei < displayedFields.size(); valuei++) {
	    		var fieldIndex = displayedFields[valuei];
	    		valstr = _getFieldValue(fieldIndex, countstr, lapstr, spdstr, absstr, laststr, diststr, trendstr);
	    		speedflag = _showsSpeedUnits(fieldIndex);
	    		distflag = _showsDistanceUnits(fieldIndex);
	    	    dc.drawText(labelX[1], labelY[valuei], mValueFont, valstr, Graphics.TEXT_JUSTIFY_LEFT);
	    	    if (speedflag) {
	    	    	// calculate location for units immediately right of speed value
	    	    	dc.drawText(labelX[1]+_getCachedValueWidth(dc, fieldIndex, valstr)+3, labelY[valuei], mUnitsFont, unitsstr, Graphics.TEXT_JUSTIFY_LEFT);
	    	    }
	    	    if (distflag) {
	    	    	// calculate location for units immediately right of distance value
	    	    	dc.drawText(labelX[1]+_getCachedValueWidth(dc, fieldIndex, valstr)+3, labelY[valuei], mUnitsFont, dunitsstr, Graphics.TEXT_JUSTIFY_LEFT);
	    	    }
	    	}
	    } else {
	    	// labels first
	    	dc.setColor(lblColor, Graphics.COLOR_TRANSPARENT);
			if (autoLabelSize != -1) {
	    		for (var labeli = 0; labeli < displayedFields.size(); labeli++) {
	    			var fieldIndex = displayedFields[labeli];
	    			dc.drawText(labelX[labeli], labelY[0], mLabelFont, labels[fieldIndex], Graphics.TEXT_JUSTIFY_CENTER);
				}
			}
	        
	        // Now let's draw the values
	        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
			fh = dc.getFontHeight(mValueFont);
	    	var valstr = 0;
	        for (var valuei = 0; valuei < displayedFields.size(); valuei++) {
	    		var fieldIndex = displayedFields[valuei];
	    		valstr = _getFieldValue(fieldIndex, countstr, lapstr, spdstr, absstr, laststr, diststr, trendstr);
	    		speedflag = _showsSpeedUnits(fieldIndex);
	    		distflag = _showsDistanceUnits(fieldIndex);
	    	    dc.drawText(labelX[valuei], labelY[1], mValueFont, valstr, Graphics.TEXT_JUSTIFY_CENTER);
	    	    if (speedflag) {
	    	    	// calculate location for units immediately below speed value
	    	    	dc.drawText(labelX[valuei], labelY[1] + fh - 5, mUnitsFont, unitsstr, Graphics.TEXT_JUSTIFY_CENTER);
	    	    }
	    	    if (distflag) {
	    	    	// calculate location for units immediately below distance value
	    	    	dc.drawText(labelX[valuei], labelY[1] + fh - 5, mUnitsFont, dunitsstr, Graphics.TEXT_JUSTIFY_CENTER);
	    	    }
	    	}
	    }
		// draw tiny sensor status indicator at bottom of field
		var radarStatusText = "START";
		if (mPendingResetTap) {
			radarStatusText = "TAP AGAIN";
		} else if (fitContributor != null) {
			radarStatusText = fitContributor.bikeRadar.getDisplayStatus();
		}
		var statusY = dc.getHeight() - dc.getFontHeight(mStatusFont) - 1;
		if (showDebugStatus || mPendingResetTap) {
			dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
			dc.drawText(dc.getWidth() / 2, statusY, mStatusFont, radarStatusText, Graphics.TEXT_JUSTIFY_CENTER);
		}
    }
    
    // activity has ended
    // handle resetting count to 0 after activity has ended
    function onTimerReset() {
		_clearPendingResetTap();
	    	if (mFitContributor != null) {
	    		mFitContributor.onTimerReset();
	    	}
    }
    
    // simply reset the lapcount ... lap data already written out once per second (per documentation) overwriting previous lap message ... this is the way it's supposed to work!
    function onTimerLap() {
	    	if (mFitContributor != null) {
	    		mFitContributor.onTimerLap();
	    	}
    }
    

}

class MyBikeTrafficViewDelegate extends WatchUi.BehaviorDelegate {

	hidden var mView as MyBikeTrafficView;

	function initialize(view as MyBikeTrafficView) {
		BehaviorDelegate.initialize();
		mView = view;
	}

	function onTap(evt as WatchUi.ClickEvent) as Lang.Boolean {
		mView.handleResetTap();
		return true;
	}
}
