using Toybox.Ant;
using Toybox.AntPlus;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

const ANT_RADAR_DEVICE_TYPE = 40;
const ANT_RADAR_MESSAGE_PERIOD = 4084;
const ANT_RADAR_RADIO_FREQUENCY = 57;
const ANT_RADAR_TRANSMISSION_TYPE = 0;
const ANT_RADAR_SEARCH_TIMEOUT_LOW = 12;
const ANT_RADAR_FALLBACK_DELAY_TICKS = 3;
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

class MyBikeAntRadarTarget {
	var range;
	var speed;
	var threat;

	function initialize(rangeMeters, speedMetersPerSecond, threatLevel) {
		range = rangeMeters;
		speed = speedMetersPerSecond;
		threat = threatLevel;
	}
}

class MyBikeRawAntRadarChannel extends Ant.GenericChannel {
	hidden var mDeviceCfg;
	hidden var mIsOpen as Lang.Boolean;
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

	hidden function _buildEmptyTargets() {
		var targets = [] as Lang.Array<MyBikeAntRadarTarget>;
		for (var i = 0; i < ANT_RADAR_TARGET_SLOTS; i++) {
			targets.add(new MyBikeAntRadarTarget(0, 0.0f, 0));
		}
		return targets;
	}

	hidden function _nowSeconds() as Lang.Number or Null {
		try {
			return Time.now().value();
		} catch(e) {}
		return null;
	}

	hidden function _clearTargets(clearAvailability as Lang.Boolean) {
		mTargets = _buildEmptyTargets();
		if (clearAvailability) {
			mHasTargetPage = false;
			mLastTargetPageTime = null;
			mLastTargetsBPageTime = null;
		}
	}

	hidden function _extract2Bits(value, index) as Lang.Number {
		return (value >> (index * 2)) & 0x03;
	}

	hidden function _extractRange(rawRanges, index) as Lang.Float {
		return (((rawRanges >> (index * 6)) & 0x3F) as Lang.Float) * ANT_RADAR_RANGE_SCALE_METERS;
	}

	hidden function _extractSpeed(payload, index) as Lang.Float {
		var sourceByte = index < 2 ? payload[6] : payload[7];
		var nibbleShift = (index % 2) * 4;
		return (((sourceByte >> nibbleShift) & 0x0F) as Lang.Float) * ANT_RADAR_SPEED_SCALE_MPS;
	}

	hidden function _parseTargets(payload, startIndex) {
		var rawRanges = payload[3] | (payload[4] << 8) | (payload[5] << 16);
		for (var i = 0; i < 4; i++) {
			var threatLevel = _extract2Bits(payload[1], i);
			var targetIndex = startIndex + i;
			if (threatLevel == 0) {
				mTargets[targetIndex] = new MyBikeAntRadarTarget(0, 0.0f, 0);
				continue;
			}

			mTargets[targetIndex] = new MyBikeAntRadarTarget(
				_extractRange(rawRanges, i),
				_extractSpeed(payload, i),
				threatLevel
			);
		}
	}

	hidden function _markTargetPage(pageNumber) {
		mHasBroadcast = true;
		mHasTargetPage = true;
		mIsSearching = false;
		mLastRfEvent = null;
		mSawErrorPage = false;
		mDeviceState = 0;
		mLastPage = pageNumber;
		mLastTargetPageTime = _nowSeconds();
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
			return;
		}

		if (mLastTargetsBPageTime != null &&
			(now - mLastTargetsBPageTime) >= ANT_RADAR_TARGETS_B_TIMEOUT_SECONDS) {
			for (var i = 4; i < ANT_RADAR_TARGET_SLOTS; i++) {
				mTargets[i] = new MyBikeAntRadarTarget(0, 0.0f, 0);
			}
			mLastTargetsBPageTime = null;
		}
	}

	hidden function _handleDeviceStatus(payload) {
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
			mIsSearching = true;
			mDeviceState = 0;
			mSawErrorPage = false;
			mIsOpen = GenericChannel.open();
			System.println("ANT raw: open=" + mIsOpen);
			return mIsOpen;
		} catch(e) {
			System.println("ANT raw: open failed");
		}

		mIsOpen = false;
		mIsSearching = false;
		return false;
	}

	function closeChannel() {
		if (!mIsOpen) {
			return;
		}

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
		var payload = msg.getPayload();
		if (Ant.MSG_ID_BROADCAST_DATA == msg.messageId && payload != null && payload.size() > 0) {
			var pageNumber = payload[0] & 0xFF;
			mLastPage = pageNumber;
			mLastRfEvent = null;
			System.println("ANT raw: page=" + mLastPage.format("%02X"));
			mDeviceCfg = GenericChannel.getDeviceConfig();

			if (pageNumber == ANT_RADAR_PAGE_TARGETS_A) {
				_markTargetPage(pageNumber);
				_parseTargets(payload, 0);
				return;
			}

			if (pageNumber == ANT_RADAR_PAGE_TARGETS_B) {
				_markTargetPage(pageNumber);
				_parseTargets(payload, 4);
				return;
			}

			if (pageNumber == ANT_RADAR_PAGE_DEVICE_STATUS) {
				_handleDeviceStatus(payload);
				return;
			}

			if (pageNumber == ANT_RADAR_PAGE_ERROR) {
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
			_restartSearch();
			return;
		}

		if (Ant.MSG_CODE_EVENT_RX_SEARCH_TIMEOUT == (payload[1] & 0xFF)) {
			mDeviceState = 0;
			mSawErrorPage = false;
			_clearTargets(true);
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
	var statusStr as Lang.String;
	hidden var mNativeRadar;
	hidden var mNativeRadarAvailable as Lang.Boolean;
	hidden var mRawRadar as MyBikeRawAntRadarChannel or Null;
	hidden var mTicksWithoutNative as Lang.Number;

	function initialize() {
		mNativeRadar = null;
		mNativeRadarAvailable = false;
		mRawRadar = null;
		mTicksWithoutNative = 0;
		statusStr = "ANT:init";

		if (AntPlus has :BikeRadar) {
			try {
				mNativeRadar = new AntPlus.BikeRadar(null);
				mNativeRadarAvailable = true;
			} catch(e) {
				statusStr = "ANT:fallback";
			}
		} else {
			statusStr = "ANT:fallback";
		}
	}

	hidden function _buildEmptyTargets() {
		var targets = [] as Lang.Array<MyBikeAntRadarTarget>;
		for (var i = 0; i < ANT_RADAR_TARGET_SLOTS; i++) {
			targets.add(new MyBikeAntRadarTarget(0, 0.0f, 0));
		}
		return targets;
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

	hidden function _stopRawFallback() {
		if (mRawRadar == null) {
			return;
		}

		mRawRadar.closeChannel();
		mRawRadar = null;
	}

	hidden function _startRawFallback() {
		if (mRawRadar != null) {
			return;
		}

		mRawRadar = new MyBikeRawAntRadarChannel();
		if (mRawRadar.openChannel()) {
			statusStr = "ANT:scan";
		} else {
			statusStr = "ANT:raw!";
		}
	}

	hidden function _updateRawStatus() as Lang.Boolean {
		if (mRawRadar == null) {
			return false;
		}

		var lastPage = mRawRadar.getLastPage();
		if (mRawRadar.isTracking()) {
			statusStr = "ANT:raw";
		} else if (lastPage != null) {
			statusStr = "ANT:p" + lastPage.format("%02X");
		} else if (mRawRadar.isSearching()) {
			statusStr = "ANT:scan";
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
			return "ANT scan timeout";
		}
		if (lastRfEvent == Ant.MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH) {
			return "ANT scan rx fail";
		}
		if (lastRfEvent == Ant.MSG_CODE_EVENT_CHANNEL_CLOSED) {
			return "ANT scan ch closed";
		}

		return "ANT scan rf " + lastRfEvent.format("%02X");
	}

	hidden function _getRawPageDisplayStatus() as Lang.String or Null {
		if (mRawRadar == null) {
			return null;
		}

		if (mRawRadar.sawErrorPage()) {
			return "ANT radar error";
		}

		var lastPage = mRawRadar.getLastPage();
		if (lastPage != ANT_RADAR_PAGE_DEVICE_STATUS) {
			return null;
		}

		var rawDeviceState = mRawRadar.getRawDeviceState();
		if (rawDeviceState == ANT_RADAR_DEVICE_STATE_SHUTDOWN_REQUESTED) {
			return "ANT shutdown req";
		}
		if (rawDeviceState == ANT_RADAR_DEVICE_STATE_SHUTDOWN_ABORTED) {
			return "ANT shutdown abort";
		}
		if (rawDeviceState == ANT_RADAR_DEVICE_STATE_SHUTDOWN_FORCED) {
			return "ANT shutdown forced";
		}

		return "ANT status page";
	}

	hidden function _normalizeNative(radarInfo) {
		var targets = _buildEmptyTargets();
		if (radarInfo == null) {
			return targets;
		}

		var limit = radarInfo.size();
		if (limit > targets.size()) {
			limit = targets.size();
		}

		for (var i = 0; i < limit; i++) {
			var target = radarInfo[i];
			if (target != null) {
				var rangeMeters = target.range != null ? target.range : 0;
				var speedMetersPerSecond = target.speed != null ? target.speed : 0.0f;
				var threatLevel = target.threat != null ? target.threat : 0;
				targets[i] = new MyBikeAntRadarTarget(
					rangeMeters,
					speedMetersPerSecond,
					threatLevel
				);
			}
		}

		return targets;
	}

	function tick() {
		var deviceState = _getNativeState();
		if (mNativeRadarAvailable) {
			if (_isNativeTracking(deviceState)) {
				mTicksWithoutNative = 0;
				_stopRawFallback();
				statusStr = "ANT:native";
				return;
			}

			if (_isNativeSearching(deviceState)) {
				mTicksWithoutNative = 0;
				_stopRawFallback();
				statusStr = "ANT:pair";
				return;
			}

			if (_updateRawStatus()) {
				return;
			}

			mTicksWithoutNative++;
			if (deviceState != null && deviceState.state != null &&
				(deviceState.state == AntPlus.DEVICE_STATE_CLOSED ||
				deviceState.state == AntPlus.DEVICE_STATE_DEAD)) {
				statusStr = "ANT:none";
			}

			if (mTicksWithoutNative < ANT_RADAR_FALLBACK_DELAY_TICKS) {
				return;
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
			if (_isNativeTracking(deviceState)) {
				return _normalizeNative(mNativeRadar.getRadarInfo());
			}
		}

		if (mRawRadar != null) {
			return mRawRadar.getRadarInfo();
		}

		return null;
	}

	function getDisplayStatus() {
		var rawScanStatus = _getRawScanDisplayStatus();
		if (rawScanStatus != null) {
			return rawScanStatus;
		}

		var rawPageStatus = _getRawPageDisplayStatus();
		if (rawPageStatus != null) {
			return rawPageStatus;
		}

		if (statusStr == "ANT:init") {
			return "ANT init";
		}
		if (statusStr == "ANT:pair") {
			return "ANT waiting pair";
		}
		if (statusStr == "ANT:none") {
			return "ANT no paired radar";
		}
		if (statusStr == "ANT:native") {
			return "ANT paired radar";
		}
		if (statusStr == "ANT:scan") {
			return "ANT raw scanning";
		}
		if (statusStr == "ANT:raw") {
			return "ANT raw tracking";
		}
		if (statusStr == "ANT:raw!") {
			return "ANT raw open failed";
		}
		if (statusStr == "ANT:fallback") {
			return "ANT raw fallback";
		}
		if (statusStr == "ANT:p01") {
			return "ANT status page";
		}
		if (statusStr == "ANT:p30") {
			return "ANT targets 1-4";
		}
		if (statusStr == "ANT:p31") {
			return "ANT targets 5-8";
		}
		if (statusStr == "ANT:p57") {
			return "ANT radar error";
		}
		if (statusStr.find("ANT:p") == 0) {
			return "ANT raw page " + statusStr.substring(5, statusStr.length());
		}
		return statusStr;
	}
}