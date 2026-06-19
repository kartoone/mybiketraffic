using Toybox.Ant;
using Toybox.AntPlus;
using Toybox.Lang;
using Toybox.Time;

const ANT_RADAR_DEVICE_TYPE = 40;
const ANT_RADAR_MESSAGE_PERIOD = 4084;
const ANT_RADAR_RADIO_FREQUENCY = 57;
const ANT_RADAR_TRANSMISSION_TYPE = 0;
const ANT_RADAR_SEARCH_TIMEOUT_LOW = 12;
const ANT_RADAR_FALLBACK_DELAY_SOMETIMES_TICKS = 120;
const ANT_RADAR_TARGET_SLOTS = 8;
const ANT_RADAR_PAGE_TARGETS_A = 0x30;
const ANT_RADAR_PAGE_TARGETS_B = 0x31;
const ANT_RADAR_PAGE_DEVICE_STATUS = 0x01;
const ANT_RADAR_PAGE_ERROR = 0x57;
const ANT_RADAR_DEVICE_STATE_SHUTDOWN_REQUESTED = 1;
const ANT_RADAR_DEVICE_STATE_SHUTDOWN_ABORTED = 2;
const ANT_RADAR_DEVICE_STATE_SHUTDOWN_FORCED = 3;
const ANT_RADAR_RANGE_SCALE_METERS = 3.125f;
const ANT_RADAR_SPEED_SCALE_MPS = 3.04f;
const ANT_RADAR_TARGET_TIMEOUT_SECONDS = 2;
const ANT_RADAR_TARGETS_B_TIMEOUT_SECONDS = 1;
const ANT_RADAR_RAW_RECOVERY_DELAY_TICKS = 2;
const ANT_RADAR_RAW_RESTART_COOLDOWN_TICKS = 8;
const ANT_RADAR_RAW_RESET_STATUS_TICKS = 3;

const CONNECTION_MODE_ALWAYS_820 = 0;
const CONNECTION_MODE_NEVER_820 = 1;
const CONNECTION_MODE_SOMETIMES_820 = 2;

class MyBikeAntRadarTarget {
	var range;
	var speed;
	var threat;

	function initialize(rangeMeters, speedMetersPerSecond, threatLevel) {
		range = rangeMeters;
		speed = speedMetersPerSecond;
		threat = threatLevel;
	}

	function set(rangeMeters, speedMetersPerSecond, threatLevel) as Void {
		range = rangeMeters;
		speed = speedMetersPerSecond;
		threat = threatLevel;
	}

	function clear() as Void {
		set(0, 0.0f, 0);
	}
}

class MyBikeRawAntRadarChannel extends Ant.GenericChannel {
	hidden var mDeviceCfg;
	hidden var mIsOpen as Lang.Boolean;
	hidden var mIntentionalClose as Lang.Boolean;
	hidden var mIsSearching as Lang.Boolean;
	hidden var mHasBroadcast as Lang.Boolean;
	hidden var mLastPage as Lang.Number or Null;
	hidden var mLastRfEvent as Lang.Number or Null;
	hidden var mTargets as Lang.Array<MyBikeAntRadarTarget>;
	hidden var mHasTargetPage as Lang.Boolean;
	hidden var mLastTargetPageTime as Lang.Number or Null;
	hidden var mLastTargetsBPageTime as Lang.Number or Null;
	hidden var mDeviceState as Lang.Number;
	hidden var mSawErrorPage as Lang.Boolean;

	function initialize() {
		var chanAssign = new Ant.ChannelAssignment(
			Ant.CHANNEL_TYPE_RX_NOT_TX,
			Ant.NETWORK_PLUS
		);
		GenericChannel.initialize(method(:onMessage), chanAssign);

		mDeviceCfg = new Ant.DeviceConfig({
			:deviceNumber => 0,
			:deviceType => ANT_RADAR_DEVICE_TYPE,
			:transmissionType => ANT_RADAR_TRANSMISSION_TYPE,
			:messagePeriod => ANT_RADAR_MESSAGE_PERIOD,
			:radioFrequency => ANT_RADAR_RADIO_FREQUENCY,
			:searchTimeoutLowPriority => ANT_RADAR_SEARCH_TIMEOUT_LOW,
			:searchThreshold => 0
		});
		GenericChannel.setDeviceConfig(mDeviceCfg);

		mIsOpen = false;
		mIntentionalClose = false;
		mIsSearching = false;
		mHasBroadcast = false;
		mLastPage = null;
		mLastRfEvent = null;
		mTargets = _buildEmptyTargets();
		mHasTargetPage = false;
		mLastTargetPageTime = null;
		mLastTargetsBPageTime = null;
		mDeviceState = 0;
		mSawErrorPage = false;
	}

	hidden function _buildEmptyTargets() as Lang.Array<MyBikeAntRadarTarget> {
		var targets = [] as Lang.Array<MyBikeAntRadarTarget>;
		for (var i = 0; i < ANT_RADAR_TARGET_SLOTS; i++) {
			targets.add(new MyBikeAntRadarTarget(0, 0.0f, 0));
		}
		return targets;
	}

	hidden function _clearTargetArray(startIndex as Lang.Number, endIndex as Lang.Number) as Void {
		for (var i = startIndex; i < endIndex; i++) {
			mTargets[i].clear();
		}
	}

	hidden function _nowSeconds() as Lang.Number or Null {
		try {
			return Time.now().value();
		} catch(e) {}
		return null;
	}

	hidden function _clearTargets(clearAvailability as Lang.Boolean) {
		_clearTargetArray(0, mTargets.size());
		if (clearAvailability) {
			mHasTargetPage = false;
			mLastTargetPageTime = null;
			mLastTargetsBPageTime = null;
		}
	}

	hidden function _extract2Bits(value as Lang.Number, index as Lang.Number) as Lang.Number {
		return (value >> (index * 2)) & 0x03;
	}

	hidden function _extractRange(rawRanges as Lang.Number, index as Lang.Number) as Lang.Float {
		return (((rawRanges >> (index * 6)) & 0x3F) as Lang.Float) * ANT_RADAR_RANGE_SCALE_METERS;
	}

	hidden function _extractSpeed(payload as Lang.Array<Lang.Number>, index as Lang.Number) as Lang.Float {
		var sourceByte = index < 2 ? payload[6] : payload[7];
		var nibbleShift = (index % 2) * 4;
		return (((sourceByte >> nibbleShift) & 0x0F) as Lang.Float) * ANT_RADAR_SPEED_SCALE_MPS;
	}

	hidden function _parseTargets(payload as Lang.Array<Lang.Number>, startIndex as Lang.Number) as Void {
		var rawRanges = payload[3] | (payload[4] << 8) | (payload[5] << 16);
		for (var i = 0; i < 4; i++) {
			var threatLevel = _extract2Bits(payload[1], i);
			var targetIndex = startIndex + i;
			if (threatLevel == 0) {
				mTargets[targetIndex].clear();
				continue;
			}

			mTargets[targetIndex].set(
				_extractRange(rawRanges, i),
				_extractSpeed(payload, i),
				threatLevel
			);
		}
	}

	hidden function _markTargetPage(pageNumber) {
		var now = _nowSeconds();
		mHasBroadcast = true;
		mHasTargetPage = true;
		mIsSearching = false;
		mLastRfEvent = null;
		mSawErrorPage = false;
		mDeviceState = 0;
		mLastPage = pageNumber;
		mLastTargetPageTime = now;
		if (pageNumber == ANT_RADAR_PAGE_TARGETS_B) {
			mLastTargetsBPageTime = mLastTargetPageTime;
		}
	}

	hidden function _clearIfStale() {
		if (!mHasTargetPage || mLastTargetPageTime == null) {
			return;
		}

		var now = _nowSeconds();
		if (now == null) {
			return;
		}

		if ((now - mLastTargetPageTime) >= ANT_RADAR_TARGET_TIMEOUT_SECONDS) {
			_clearTargets(true);
			if (mLastPage == ANT_RADAR_PAGE_TARGETS_A ||
				mLastPage == ANT_RADAR_PAGE_TARGETS_B) {
				mLastPage = null;
			}
			return;
		}

		if (mLastTargetsBPageTime != null &&
			(now - mLastTargetsBPageTime) >= ANT_RADAR_TARGETS_B_TIMEOUT_SECONDS) {
			_clearTargetArray(4, ANT_RADAR_TARGET_SLOTS);
			mLastTargetsBPageTime = null;
		}
	}

	hidden function _handleDeviceStatus(payload as Lang.Array<Lang.Number>) as Void {
		mHasBroadcast = true;
		mIsSearching = false;
		mLastRfEvent = null;
		mLastPage = ANT_RADAR_PAGE_DEVICE_STATUS;
		mDeviceState = payload[1] & 0x03;
		var clearTargets = (payload[7] & 0x01) == 0;
		if (clearTargets ||
			mDeviceState == ANT_RADAR_DEVICE_STATE_SHUTDOWN_REQUESTED ||
			mDeviceState == ANT_RADAR_DEVICE_STATE_SHUTDOWN_FORCED) {
			_clearTargets(true);
		}
	}

	hidden function _restartSearch() {
		mIsOpen = false;
		mIsSearching = false;
		mHasBroadcast = false;
		mLastPage = null;
		openChannel();
	}

	function openChannel() as Lang.Boolean {
		if (mIsOpen) {
			return true;
		}

		try {
			_clearTargets(true);
			mHasBroadcast = false;
			mLastPage = null;
			mLastRfEvent = null;
			mIntentionalClose = false;
			mIsSearching = true;
			mDeviceState = 0;
			mSawErrorPage = false;
			mIsOpen = GenericChannel.open();
			return mIsOpen;
		} catch(e) {}

		mIsOpen = false;
		mIsSearching = false;
		return false;
	}

	function closeChannel() {
		if (!mIsOpen) {
			return;
		}

		mIntentionalClose = true;

		try {
			GenericChannel.close();
		} catch(e) {}

		mIsOpen = false;
		mIsSearching = false;
		mHasBroadcast = false;
		mLastPage = null;
		mDeviceState = 0;
		mSawErrorPage = false;
		_clearTargets(true);
	}

	function onMessage(msg as Ant.Message) as Void {
		var payload = msg.getPayload() as Lang.Array<Lang.Number> or Null;
		if ((Ant.MSG_ID_BROADCAST_DATA == msg.messageId ||
			Ant.MSG_ID_ACKNOWLEDGED_DATA == msg.messageId) &&
			payload != null && payload.size() > 0) {
			var pageNumber = payload[0] & 0xFF;
			mLastRfEvent = null;

			if (pageNumber == ANT_RADAR_PAGE_TARGETS_A) {
				mLastPage = pageNumber;
				_markTargetPage(pageNumber);
				_parseTargets(payload, 0);
				return;
			}

			if (pageNumber == ANT_RADAR_PAGE_TARGETS_B) {
				mLastPage = pageNumber;
				_markTargetPage(pageNumber);
				_parseTargets(payload, 4);
				return;
			}

			if (pageNumber == ANT_RADAR_PAGE_DEVICE_STATUS) {
				mLastPage = pageNumber;
				_handleDeviceStatus(payload);
				return;
			}

			if (pageNumber == ANT_RADAR_PAGE_ERROR) {
				mLastPage = pageNumber;
				mHasBroadcast = true;
				mIsSearching = false;
				mSawErrorPage = true;
				_clearTargets(true);
				return;
			}

			mHasBroadcast = true;
			mIsSearching = false;
			return;
		}

		if (Ant.MSG_ID_CHANNEL_RESPONSE_EVENT != msg.messageId || payload == null) {
			return;
		}

		if (Ant.MSG_ID_RF_EVENT != (payload[0] & 0xFF)) {
			return;
		}

		mLastRfEvent = payload[1] & 0xFF;

		if (Ant.MSG_CODE_EVENT_CHANNEL_CLOSED == (payload[1] & 0xFF)) {
			mDeviceState = 0;
			mSawErrorPage = false;
			_clearTargets(true);
			if (mIntentionalClose) {
				return;
			}
			_restartSearch();
			return;
		}

		if (Ant.MSG_CODE_EVENT_RX_SEARCH_TIMEOUT == (payload[1] & 0xFF)) {
			mDeviceState = 0;
			mSawErrorPage = false;
			_clearTargets(true);
			if (mIntentionalClose) {
				return;
			}
			_restartSearch();
			return;
		}

		if (Ant.MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH == (payload[1] & 0xFF)) {
			mIsSearching = true;
			mLastPage = null;
		}
	}

	function isOpen() as Lang.Boolean {
		return mIsOpen;
	}

	function isSearching() as Lang.Boolean {
		return mIsSearching;
	}

	function isTracking() as Lang.Boolean {
		_clearIfStale();
		return mHasTargetPage && !mSawErrorPage;
	}

	function getLastPage() as Lang.Number or Null {
		return mLastPage;
	}

	function getLastRfEvent() as Lang.Number or Null {
		return mLastRfEvent;
	}

	function getRawDeviceState() as Lang.Number {
		return mDeviceState;
	}

	function sawErrorPage() as Lang.Boolean {
		return mSawErrorPage;
	}

	function getRadarInfo() {
		_clearIfStale();
		if (!mHasTargetPage || mSawErrorPage) {
			return null;
		}
		return mTargets;
	}
}

class MyBikeAntRadar {
	hidden var mStatusCode as Lang.String;
	hidden var mConnectionBehaviorMode as Lang.Number;
	hidden var mSkipWaitForNew820SecureBluetooth as Lang.Boolean;
	hidden var mUseNativeOnly as Lang.Boolean;
	hidden var mManualRawResetPending as Lang.Boolean;
	hidden var mNativeRadar;
	hidden var mNativeRadarAvailable as Lang.Boolean;
	hidden var mRawRadar as MyBikeRawAntRadarChannel or Null;
	hidden var mNativeSessionLocked as Lang.Boolean;
	hidden var mRawInvalidTicks as Lang.Number;
	hidden var mRawRestartCooldownTicks as Lang.Number;
	hidden var mRawResetStatusTicks as Lang.Number;
	hidden var mTicksWithoutNative as Lang.Number;
	hidden var mSkipWaitOnce as Lang.Boolean;
	hidden var mNormalizedNativeTargets as Lang.Array<MyBikeAntRadarTarget>;

	function initialize(connectionBehaviorMode as Lang.Object or Null) {
		mConnectionBehaviorMode = CONNECTION_MODE_NEVER_820;
		if (connectionBehaviorMode != null) {
			if (connectionBehaviorMode instanceof Lang.Number) {
				mConnectionBehaviorMode = connectionBehaviorMode as Lang.Number;
			} else if (connectionBehaviorMode instanceof Lang.Boolean) {
				var legacySkipWait = connectionBehaviorMode as Lang.Boolean;
				mConnectionBehaviorMode = legacySkipWait ? CONNECTION_MODE_ALWAYS_820 : CONNECTION_MODE_SOMETIMES_820;
			}
		}
		mSkipWaitForNew820SecureBluetooth = mConnectionBehaviorMode == CONNECTION_MODE_ALWAYS_820;
		mUseNativeOnly = mConnectionBehaviorMode == CONNECTION_MODE_NEVER_820;
		mManualRawResetPending = false;
		mNativeRadar = null;
		mNativeRadarAvailable = false;
		mRawRadar = null;
		mNativeSessionLocked = false;
		mRawInvalidTicks = 0;
		mRawRestartCooldownTicks = 0;
		mRawResetStatusTicks = 0;
		mTicksWithoutNative = 0;
		mSkipWaitOnce = false;
		mNormalizedNativeTargets = _buildEmptyTargets();
		mStatusCode = "init";

		if (AntPlus has :BikeRadar) {
			try {
				mNativeRadar = new AntPlus.BikeRadar(null);
				mNativeRadarAvailable = true;
			} catch(e) {
				mStatusCode = "fallback";
			}
		} else {
			mStatusCode = "fallback";
		}
	}

	hidden function _buildEmptyTargets() as Lang.Array<MyBikeAntRadarTarget> {
		var targets = [] as Lang.Array<MyBikeAntRadarTarget>;
		for (var i = 0; i < ANT_RADAR_TARGET_SLOTS; i++) {
			targets.add(new MyBikeAntRadarTarget(0, 0.0f, 0));
		}
		return targets;
	}

	hidden function _clearNormalizedNativeTargets() as Void {
		for (var i = 0; i < mNormalizedNativeTargets.size(); i++) {
			mNormalizedNativeTargets[i].clear();
		}
	}

	hidden function _getNativeState() {
		if (!mNativeRadarAvailable || mNativeRadar == null) {
			return null;
		}

		try {
			return mNativeRadar.getDeviceState();
		} catch(e) {}
		return null;
	}

	hidden function _isNativeTracking(deviceState) as Lang.Boolean {
		return deviceState != null &&
			deviceState.state != null &&
			deviceState.state == AntPlus.DEVICE_STATE_TRACKING;
	}

	hidden function _isNativeSearching(deviceState) as Lang.Boolean {
		return deviceState != null &&
			deviceState.state != null &&
			deviceState.state == AntPlus.DEVICE_STATE_SEARCHING;
	}

	hidden function _clearRawRecoveryState() {
		mRawInvalidTicks = 0;
		mRawRestartCooldownTicks = 0;
		mRawResetStatusTicks = 0;
		mManualRawResetPending = false;
	}

	hidden function _stopRawFallback() {
		if (mRawRadar == null) {
			_clearRawRecoveryState();
			return;
		}

		mRawRadar.closeChannel();
		mRawRadar = null;
		_clearRawRecoveryState();
	}

	hidden function _startRawFallback() {
		if (mRawRadar != null) {
			return;
		}

		mSkipWaitOnce = false;

		mRawRadar = new MyBikeRawAntRadarChannel();
		if (mRawRadar.openChannel()) {
			mStatusCode = "scan";
		} else {
			mStatusCode = "raw_fail";
			mManualRawResetPending = false;
		}
	}

	hidden function _restartRawFallback() {
		_stopRawFallback();
		mRawInvalidTicks = 0;
		mRawRestartCooldownTicks = ANT_RADAR_RAW_RESTART_COOLDOWN_TICKS;
		_startRawFallback();
		if (mRawRadar != null && mRawRadar.isOpen()) {
			mRawResetStatusTicks = ANT_RADAR_RAW_RESET_STATUS_TICKS;
		}
	}

	hidden function _tickRawRecoveryState() {
		if (mRawRestartCooldownTicks > 0) {
			mRawRestartCooldownTicks--;
		}
		if (mRawResetStatusTicks > 0) {
			mRawResetStatusTicks--;
		}
	}

	hidden function _shouldRestartRawFallback(rawTracking, rawSearching, rawLastPage, rawLastRfEvent) as Lang.Boolean {
		if (mRawRadar == null || rawTracking) {
			return false;
		}

		if (mRawRadar.sawErrorPage()) {
			return true;
		}

		if (rawLastRfEvent == Ant.MSG_CODE_EVENT_CHANNEL_CLOSED ||
			rawLastRfEvent == Ant.MSG_CODE_EVENT_RX_SEARCH_TIMEOUT ||
			rawLastRfEvent == Ant.MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH) {
			return true;
		}

		if (rawSearching) {
			return false;
		}

		return rawLastPage != ANT_RADAR_PAGE_DEVICE_STATUS;
	}

	hidden function _updateRawStatus() as Lang.Boolean {
		if (mRawRadar == null) {
			return false;
		}

		var lastPage = mRawRadar.getLastPage();
		if (mRawRadar.isTracking()) {
			mManualRawResetPending = false;
			mStatusCode = "raw";
		} else if (lastPage != null) {
			mManualRawResetPending = false;
			mStatusCode = "page_" + lastPage.format("%02X");
		} else if (mRawRadar.isSearching()) {
			mManualRawResetPending = false;
			mStatusCode = "scan";
		}

		return true;
	}

	hidden function _getRawScanDisplayStatus() as Lang.String or Null {
		if (mRawRadar == null || !mRawRadar.isSearching()) {
			return null;
		}

		var lastRfEvent = mRawRadar.getLastRfEvent();
		if (lastRfEvent == null) {
			return null;
		}

		if (lastRfEvent == Ant.MSG_CODE_EVENT_RX_SEARCH_TIMEOUT) {
			return "TIMEOUT";
		}
		if (lastRfEvent == Ant.MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH) {
			return "SCANFAIL";
		}
		if (lastRfEvent == Ant.MSG_CODE_EVENT_CHANNEL_CLOSED) {
			return "CLOSED";
		}

		return "SCANNING";
	}

	hidden function _getRawPageDisplayStatus() as Lang.String or Null {
		if (mRawRadar == null) {
			return null;
		}

		if (mRawRadar.sawErrorPage()) {
			return "ERROR";
		}

		var lastPage = mRawRadar.getLastPage();
		if (lastPage != ANT_RADAR_PAGE_DEVICE_STATUS) {
			return null;
		}

		var rawDeviceState = mRawRadar.getRawDeviceState();
		if (rawDeviceState == ANT_RADAR_DEVICE_STATE_SHUTDOWN_REQUESTED) {
			return "SHUTREQ";
		}
		if (rawDeviceState == ANT_RADAR_DEVICE_STATE_SHUTDOWN_ABORTED) {
			return "SHUTABRT";
		}
		if (rawDeviceState == ANT_RADAR_DEVICE_STATE_SHUTDOWN_FORCED) {
			return "SHUTFORCE";
		}

		return "STATUS";
	}

	hidden function _normalizeNative(radarInfo as Lang.Array<AntPlus.RadarTarget> or Null) as Lang.Array<MyBikeAntRadarTarget> {
		_clearNormalizedNativeTargets();
		if (radarInfo == null) {
			return mNormalizedNativeTargets;
		}

		var limit = radarInfo.size();
		if (limit > mNormalizedNativeTargets.size()) {
			limit = mNormalizedNativeTargets.size();
		}

		for (var i = 0; i < limit; i++) {
			var target = radarInfo[i] as AntPlus.RadarTarget or Null;
			if (target == null) {
				continue;
			}
			mNormalizedNativeTargets[i].set(
				target.range,
				target.speed,
				target.threat
			);
		}

		return mNormalizedNativeTargets;
	}

	function tick() {
		var deviceState = _getNativeState();
		var nativeTracking = _isNativeTracking(deviceState);
		var nativeSearching = _isNativeSearching(deviceState);
		var rawTracking = mRawRadar != null && mRawRadar.isTracking();
		var rawSearching = mRawRadar != null && mRawRadar.isSearching();
		var rawLastPage = mRawRadar != null ? mRawRadar.getLastPage() : null;
		var rawLastRfEvent = mRawRadar != null ? mRawRadar.getLastRfEvent() : null;

		if (nativeTracking) {
			mManualRawResetPending = false;
			mNativeSessionLocked = true;
		}

		if (mNativeRadarAvailable && (mNativeSessionLocked || nativeSearching)) {
			mRawInvalidTicks = 0;
			_stopRawFallback();
			if (nativeTracking) {
				mTicksWithoutNative = 0;
				mStatusCode = "native";
			} else if (nativeSearching) {
				mManualRawResetPending = false;
				mTicksWithoutNative = 0;
				mStatusCode = "pair";
			} else {
				mStatusCode = "wait";
			}
			return;
		}

		if (mUseNativeOnly) {
			_stopRawFallback();
			if (mNativeRadarAvailable) {
				mStatusCode = "wait";
			} else {
				mStatusCode = "fallback";
			}
			return;
		}

		_tickRawRecoveryState();

		if (mNativeRadarAvailable) {
			if (mRawRadar != null) {
				if (_shouldRestartRawFallback(rawTracking, rawSearching, rawLastPage, rawLastRfEvent)) {
					mRawInvalidTicks++;
					if (mRawRestartCooldownTicks == 0 &&
						mRawInvalidTicks >= ANT_RADAR_RAW_RECOVERY_DELAY_TICKS) {
						_restartRawFallback();
						_updateRawStatus();
						return;
					}
				} else {
					mRawInvalidTicks = 0;
				}

				_updateRawStatus();
				return;
			}

			if (!rawTracking) {
				mTicksWithoutNative++;
				if (mConnectionBehaviorMode == CONNECTION_MODE_SOMETIMES_820 &&
					!mSkipWaitOnce &&
					mTicksWithoutNative < ANT_RADAR_FALLBACK_DELAY_SOMETIMES_TICKS) {
					mStatusCode = "wait";
					return;
				}
			}
		}

		_startRawFallback();
		if (_updateRawStatus()) {
			return;
		}
	}

	function getRadarInfo() {
		if (mNativeRadarAvailable) {
			var deviceState = _getNativeState();
			var nativeTracking = _isNativeTracking(deviceState);
			if (mNativeSessionLocked || nativeTracking) {
				if (!nativeTracking) {
					return null;
				}
				return _normalizeNative(mNativeRadar.getRadarInfo());
			}
		}

		if (mRawRadar != null) {
			return mRawRadar.getRadarInfo();
		}

		return null;
	}

	function isTracking() as Lang.Boolean {
		if (mNativeRadarAvailable) {
			var deviceState = _getNativeState();
			var nativeTracking = _isNativeTracking(deviceState);
			if (mNativeSessionLocked || nativeTracking) {
				return nativeTracking;
			}
		}

		return mRawRadar != null && mRawRadar.isTracking();
	}

	function requestRawWaitReset() as Void {
		_stopRawFallback();
		mNativeSessionLocked = false;
		if (mUseNativeOnly) {
			mManualRawResetPending = false;
			mRawResetStatusTicks = 0;
			if (AntPlus has :BikeRadar) {
				try {
					mNativeRadar = new AntPlus.BikeRadar(null);
					mNativeRadarAvailable = true;
					mStatusCode = "pair";
				} catch(e) {
					mNativeRadar = null;
					mNativeRadarAvailable = false;
					mStatusCode = "fallback";
				}
			}
		} else {
			mManualRawResetPending = true;
			mRawResetStatusTicks = ANT_RADAR_RAW_RESET_STATUS_TICKS;
			if (mConnectionBehaviorMode == CONNECTION_MODE_SOMETIMES_820) {
				// Double-tap reset in "sometimes" mode means skip the long wait once.
				mSkipWaitOnce = true;
			}
		}
		mTicksWithoutNative = 0;
		mStatusCode = "init";

		if (mNativeRadarAvailable &&
			mConnectionBehaviorMode == CONNECTION_MODE_SOMETIMES_820 &&
			!mSkipWaitOnce) {
			mManualRawResetPending = false;
			mRawResetStatusTicks = 0;
			mStatusCode = "wait";
			return;
		}
	}

	hidden function _getLiveDisplayFallback() as Lang.String {
		var deviceState = _getNativeState();
		if (_isNativeTracking(deviceState)) {
			return "PAIRED";
		}
		if (_isNativeSearching(deviceState)) {
			return "PAIR";
		}

		if (mRawRadar != null) {
			if (mRawRadar.isTracking()) {
				return "820 OK";
			}
			if (mRawRadar.isSearching()) {
				return "SCAN";
			}
		}

		if (mNativeRadarAvailable) {
			return "WAIT";
		}

		return "RADAR";
	}

	function getDisplayStatus() {
		if (mManualRawResetPending || mRawResetStatusTicks > 0) {
			return "RESET";
		}

		if (mStatusCode == "wait") {
			return "WAIT";
		}

		var rawScanStatus = _getRawScanDisplayStatus();
		if (rawScanStatus != null) {
			return rawScanStatus;
		}

		var rawPageStatus = _getRawPageDisplayStatus();
		if (rawPageStatus != null) {
			return rawPageStatus;
		}

		if (mStatusCode == "init") {
			return "INIT";
		}
		if (mStatusCode == "pair") {
			return "PAIR";
		}
		if (mStatusCode == "none") {
			return "NONE";
		}
		if (mStatusCode == "native") {
			return "PAIRED";
		}
		if (mStatusCode == "scan") {
			return "SCAN";
		}
		if (mStatusCode == "raw") {
			return "820 OK";
		}
		if (mStatusCode == "raw_fail") {
			return "RAWFAIL";
		}
		if (mStatusCode == "fallback") {
			return "FALLBACK";
		}
		if (mStatusCode == "page_01") {
			return "STATUS";
		}
		if (mStatusCode == "page_30") {
			return "TARGETS";
		}
		if (mStatusCode == "page_31") {
			return "TARGETS";
		}
		if (mStatusCode == "page_57") {
			return "ERROR";
		}
		if (mStatusCode.find("page_") == 0) {
			return "PAGE";
		}
		return _getLiveDisplayFallback();
	}
}
