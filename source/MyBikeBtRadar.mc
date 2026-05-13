using Toybox.BluetoothLowEnergy;
using Toybox.System;
using Toybox.Lang;

const VARIA_SERVICE_UUID_STR = "6A4E3200-667B-11E3-949A-0800200C9A66";
const VARIA_CHAR_3203_STR    = "6A4E3203-667B-11E3-949A-0800200C9A66";
const GARMIN_COMPANY_ID      = 0x0087;

const V1_SEQ_NIBBLE = 0x02;
const BLE_STATUS_GATT_INSUFFICIENT_AUTHENTICATION = 18;
const BLE_STATUS_GATT_INSUFFICIENT_ENCRYPTION     = 19;

class MyBikeBtRadarDelegate extends BluetoothLowEnergy.BleDelegate {
    hidden var mRadar;
    hidden var mCccd as BluetoothLowEnergy.Descriptor or Null;
    hidden var mDevice as BluetoothLowEnergy.Device or Null;
    hidden var mRetry as Lang.Number;
    hidden var mSecureBondingEnabled as Lang.Boolean;

    function initialize(radar) {
        BleDelegate.initialize();
        mRadar = radar;
        mCccd  = null;
        mDevice = null;
        mRetry = 0;
        mSecureBondingEnabled = false;

        if (BluetoothLowEnergy has :setConnectionStrategy &&
            BluetoothLowEnergy has :CONNECTION_STRATEGY_SECURE_PAIR_BOND) {
            try {
                BluetoothLowEnergy.setConnectionStrategy(
                    BluetoothLowEnergy.CONNECTION_STRATEGY_SECURE_PAIR_BOND
                );
                mSecureBondingEnabled = true;
                System.println("BLE: secure pair+bond enabled");
            } catch(e) {
                System.println("BLE: secure pair+bond unavailable");
            }
        }
    }

    hidden function _beginSubscription(device) {
        if (device == null) {
            return;
        }

        var svc = device.getService(
            BluetoothLowEnergy.stringToUuid(VARIA_SERVICE_UUID_STR)
        );
        if (svc == null) {
            mRadar.statusStr = "BLE:nosvc";
            System.println("BLE: no service");
            return;
        }

        var chr = svc.getCharacteristic(
            BluetoothLowEnergy.stringToUuid(VARIA_CHAR_3203_STR)
        );
        if (chr == null) {
            mRadar.statusStr = "BLE:nochr";
            System.println("BLE: no char 3203");
            return;
        }

        mCccd = chr.getDescriptor(BluetoothLowEnergy.cccdUuid());
        if (mCccd == null) {
            mRadar.statusStr = "BLE:nodsc";
            System.println("BLE: no CCCD descriptor");
            return;
        }

        System.println("BLE: requesting CCCD read");
        mCccd.requestRead();
        mRadar.statusStr = "BLE:rd";
    }

    hidden function _isAuthFailure(status) {
        return status == BLE_STATUS_GATT_INSUFFICIENT_AUTHENTICATION ||
            status == BLE_STATUS_GATT_INSUFFICIENT_ENCRYPTION;
    }

    hidden function _isRadarName(name) {
        if (name == null) {
            return false;
        }

        var lowerName = (name as Lang.String).toLower();
        return lowerName.find("varia") != null ||
            lowerName.find("rearvue") != null ||
            lowerName.find("rtl") != null ||
            lowerName.find("rct") != null;
    }

    hidden function _hasGarminManufacturerData(scanResult) {
        var entries = scanResult.getManufacturerSpecificDataIterator();
        if (entries == null) {
            return false;
        }

        var entry = entries.next() as Lang.Dictionary or Null;
        while (entry != null) {
            if (entry.hasKey(:companyId) &&
                (entry[:companyId] as Lang.Number) == GARMIN_COMPANY_ID) {
                return true;
            }
            entry = entries.next() as Lang.Dictionary or Null;
        }

        return false;
    }

    hidden function _updateScanStatus(scanResult, sawGarminData) {
        if (sawGarminData) {
            mRadar.statusStr = "BLE:g87";
            return;
        }

        var name = scanResult.getDeviceName();
        if (name != null) {
            mRadar.statusStr = "BLE:seen";
        } else {
            mRadar.statusStr = "BLE:adv";
        }
    }

    hidden function _matchesRadar(scanResult, serviceUuid) {
        var name = scanResult.getDeviceName();
        var serviceData = scanResult.getServiceData(serviceUuid);
        if (serviceData != null) {
            System.println("BLE: matched Varia service data");
            return true;
        }

        var uuids = scanResult.getServiceUuids();
        if (uuids != null) {
            var uuid = uuids.next() as BluetoothLowEnergy.Uuid or Null;
            while (uuid != null) {
                if (uuid.equals(serviceUuid)) {
                    System.println("BLE: matched Varia service UUID");
                    return true;
                }
                uuid = uuids.next() as BluetoothLowEnergy.Uuid or Null;
            }
        }

        if (_isRadarName(name)) {
            System.println("BLE: matched radar name=" + name);
            return true;
        }

        var sawGarminData = _hasGarminManufacturerData(scanResult);
        if (sawGarminData) {
            System.println("BLE: Garmin manufacturer data seen");
        }

        if (name != null) {
            System.println("BLE: scan name=" + name);
        }

        _updateScanStatus(scanResult, sawGarminData);
        return false;
    }

    hidden function _pairScanResult(scanResult, statusText, logText) {
        System.println(logText);
        try {
            BluetoothLowEnergy.setScanState(
                BluetoothLowEnergy.SCAN_STATE_OFF
            );
        } catch(e) {}

        mRadar.statusStr = statusText;
        try {
            BluetoothLowEnergy.pairDevice(scanResult);
        } catch(e) {
            mRadar.statusStr = "BLE:pair!";
            System.println("BLE: pair failed");
            try {
                BluetoothLowEnergy.setScanState(
                    BluetoothLowEnergy.SCAN_STATE_SCANNING
                );
            } catch(e2) {}
        }
    }

    function pairBondedRadar() {
        if (!(BluetoothLowEnergy has :getBondedDevices)) {
            return false;
        }

        var serviceUuid = BluetoothLowEnergy.stringToUuid(VARIA_SERVICE_UUID_STR);
        try {
            var results = BluetoothLowEnergy.getBondedDevices();
            var result = results.next() as BluetoothLowEnergy.ScanResult or Null;
            while (result != null) {
                var scanResult = result as BluetoothLowEnergy.ScanResult;
                if (_matchesRadar(scanResult, serviceUuid)) {
                    _pairScanResult(scanResult, "BLE:bond", "BLE: found bonded radar");
                    return true;
                }
                result = results.next() as BluetoothLowEnergy.ScanResult or Null;
            }
        } catch(e) {}

        return false;
    }

    // =========================================================================
    // Scan
    // =========================================================================

    function onScanStateChange(scanState, status) {
        System.println("BLE: scan state=" + scanState + " status=" + status);
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            mRadar.statusStr = "BLE:scn!";
        } else if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING &&
                   mRadar.statusStr == "BLE:scan") {
            mRadar.statusStr = "BLE:scn+";
        }
    }

    function onScanResults(results) {
        var serviceUuid = BluetoothLowEnergy.stringToUuid(VARIA_SERVICE_UUID_STR);
        var result = results.next() as BluetoothLowEnergy.ScanResult or Null;
        while (result != null) {
            var scanResult = result as BluetoothLowEnergy.ScanResult;
            if (_matchesRadar(scanResult, serviceUuid)) {
                _pairScanResult(scanResult, "BLE:pair", "BLE: found radar");
                return;
            }
            result = results.next() as BluetoothLowEnergy.ScanResult or Null;
        }
    }

    // =========================================================================
    // Connection
    // =========================================================================

    function onConnectedStateChanged(device, state) {
        System.println("BLE: state=" + state);
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            System.println("BLE: connected");
            mDevice = device;
            mRadar.isConnected = false;
            mRadar.statusStr   = "BLE:conn";
            mCccd = null;
            mRetry = 0;

            if (mSecureBondingEnabled) {
                mRadar.statusStr = "BLE:auth";
                System.println("BLE: waiting for encryption");
                return;
            }

            _beginSubscription(device);
        } else {
            System.println("BLE: disconnected");
            mDevice = null;
            mCccd = null;
            mRetry = 0;
            mRadar.reset();
            try {
                BluetoothLowEnergy.setScanState(
                    BluetoothLowEnergy.SCAN_STATE_SCANNING
                );
            } catch(e) {}
        }
    }

    // =========================================================================
    // Descriptor callbacks
    // =========================================================================

    function onEncryptionStatus(device, status) {
        System.println("BLE: encryption status=" + status);
        if (mDevice == null || device != mDevice) {
            return;
        }

        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            System.println("BLE: encryption ready");
            _beginSubscription(device);
        } else {
            mRadar.statusStr = "BLE:auth!";
            System.println("BLE: encryption failed");
        }
    }

    function onDescriptorRead(descriptor, status, value) {
        var valStr = "null";
        if (value != null) {
            var ba = value as Lang.ByteArray;
            valStr = "";
            for (var i = 0; i < ba.size(); i++) {
                valStr = valStr + ba[i].format("%02X");
            }
        }
        System.println("BLE: CCCD read status=" + status + " value=" + valStr);
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            if (_isAuthFailure(status)) {
                mRadar.statusStr = "BLE:auth";
                System.println("BLE: CCCD read waiting for auth");
            } else {
                mRadar.statusStr = "BLE:rd!";
            }
            return;
        }

        if (mCccd != null) {
            System.println("BLE: writing CCCD [0x01, 0x00]");
            mCccd.requestWrite([0x01, 0x00]b);
            mRadar.statusStr = "BLE:cccd";
        }
    }

    function onDescriptorWrite(descriptor, status) {
        System.println("BLE: CCCD write status=" + status);
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            mRetry = 0;
            mRadar.statusStr = "BLE:sub2";
            System.println("BLE: subscribed");
        } else if (_isAuthFailure(status)) {
            mRadar.statusStr = "BLE:auth";
            System.println("BLE: CCCD write waiting for auth");
        } else if (status == BluetoothLowEnergy.STATUS_WRITE_FAIL &&
                   mRetry < 5 && mCccd != null) {
            mRetry++;
            mRadar.statusStr = "BLE:r" + mRetry.format("%d");
            System.println("BLE: retry " + mRetry.format("%d"));
            mCccd.requestWrite([0x01, 0x00]b);
        }
    }

    // =========================================================================
    // Notifications
    // =========================================================================

    function onCharacteristicChanged(characteristic, value) {
        mRadar.onNotification(value);
    }

}

class MyBikeBtRadar {
    var vehicles as Lang.Array<Lang.Array>;
    var isConnected as Lang.Boolean;
    var statusStr as Lang.String;
    hidden var mDelegate;
    hidden var mPrevSeq as Lang.Number or Null;
    hidden var mPrevVehicles as Lang.Array<Lang.Array>;
    hidden var mTrackState as Lang.Dictionary<Lang.Number, Lang.Dictionary>;

    function initialize() {
        vehicles    = [] as Lang.Array<Lang.Array>;
        isConnected = false;
        statusStr = "BLE:scan";
        mPrevSeq      = null;
        mPrevVehicles = [] as Lang.Array<Lang.Array>;
        mTrackState   = {} as Lang.Dictionary<Lang.Number, Lang.Dictionary>;
        mDelegate = new MyBikeBtRadarDelegate(self);
        BluetoothLowEnergy.setDelegate(mDelegate);
        BluetoothLowEnergy.registerProfile({
            :uuid => BluetoothLowEnergy.stringToUuid(VARIA_SERVICE_UUID_STR),
            :characteristics => [
                {
                    :uuid => BluetoothLowEnergy.stringToUuid(VARIA_CHAR_3203_STR),
                    :descriptors => [BluetoothLowEnergy.cccdUuid()]
                }
            ]
        });
        if (!mDelegate.pairBondedRadar()) {
            BluetoothLowEnergy.setScanState(
                BluetoothLowEnergy.SCAN_STATE_SCANNING
            );
        }
    }

    // =========================================================================
    // Tick
    // =========================================================================

    function tick() {}

    function reset() {
        vehicles    = [] as Lang.Array<Lang.Array>;
        isConnected = false;
        statusStr = "BLE:scan";
        mPrevSeq      = null;
        mPrevVehicles = [] as Lang.Array<Lang.Array>;
        mTrackState   = {} as Lang.Dictionary<Lang.Number, Lang.Dictionary>;
    }

    function getDisplayStatus() {
        if (statusStr == "BLE:scan") {
            return "BLE scanning";
        }
        if (statusStr == "BLE:scn+") {
            return "BLE scan active";
        }
        if (statusStr == "BLE:scn!") {
            return "BLE scan failed";
        }
        if (statusStr == "BLE:adv") {
            return "BLE saw unnamed advert";
        }
        if (statusStr == "BLE:seen") {
            return "BLE saw named advert";
        }
        if (statusStr == "BLE:g87") {
            return "BLE Garmin advert";
        }
        if (statusStr == "BLE:bond") {
            return "BLE reconnect bonded";
        }
        if (statusStr == "BLE:pair") {
            return "BLE pairing radar";
        }
        if (statusStr == "BLE:pair!") {
            return "BLE pair failed";
        }
        if (statusStr == "BLE:conn") {
            return "BLE link connected";
        }
        if (statusStr == "BLE:auth") {
            return "BLE waiting auth";
        }
        if (statusStr == "BLE:auth!") {
            return "BLE auth failed";
        }
        if (statusStr == "BLE:nosvc") {
            return "BLE no radar service";
        }
        if (statusStr == "BLE:nochr") {
            return "BLE no radar char";
        }
        if (statusStr == "BLE:nodsc") {
            return "BLE no CCCD";
        }
        if (statusStr == "BLE:rd") {
            return "BLE reading CCCD";
        }
        if (statusStr == "BLE:rd!") {
            return "BLE CCCD read failed";
        }
        if (statusStr == "BLE:cccd") {
            return "BLE enabling notify";
        }
        if (statusStr == "BLE:sub2") {
            return "BLE subscribed";
        }
        if (statusStr == "BLE:ok") {
            return "BLE radar streaming";
        }
        if (statusStr.find("BLE:r") == 0) {
            return "BLE retry " + statusStr.substring(5, statusStr.length());
        }
        return statusStr;
    }

    // =========================================================================
    // Notification parser
    // =========================================================================

    function onNotification(value) {
        var bytes = value as Lang.ByteArray;
        var len = bytes.size();
        if (len == 0) {
            return;
        }
        // Debug hex dump
        var dump = "";
        for (var d = 0; d < len; d++) {
            dump += bytes[d].format("%02X") + " ";
        }
        System.println("BLE RX: " + dump);
        // All V1 packets have low nibble 0x02
        if ((bytes[0] & 0x0F) != V1_SEQ_NIBBLE) {
            return;
        }

        // =========================================================================
        // Heartbeat packet
        // =========================================================================

        if (len == 1) {
            isConnected = true;
            statusStr = "BLE:ok";
            vehicles = [] as Lang.Array<Lang.Array>;
            _pruneTrackState([] as Lang.Array<Lang.Array>);
            return;
        }

        // =========================================================================
        // Threat packet validation
        // =========================================================================

        if (((len - 1) % 3) != 0) {
            return;
        }
        var nowMs = System.getTimer();
        var seqByte = bytes[0];
        var newVehicles = [] as Lang.Array<Lang.Array>;
        var n = (len - 1) / 3;
        for (var i = 0; i < n; i++) {
            var vid  = bytes[1 + 3 * i];
            var dist = bytes[1 + 3 * i + 1];
            var flag = bytes[1 + 3 * i + 2];

            // bit 7 must be set
            // 0xFD reserved
            // 0xFF distance invalid
            if (vid < 0x80 || vid == 0xFD) {
                continue;
            }
            if (dist == 0xFF) {
                continue;
            }
            var trackId = vid & 0x7F;
            var speedMps = 0.0f;

            // =========================================================================
            // Speed estimate
            // =========================================================================
            var prev = mTrackState.get(trackId) as Lang.Dictionary or Null;
            if (prev != null) {
                var dt =
                    nowMs -
                    (prev.get(:timeMs) as Lang.Number);
                if (dt > 0) {
                    var s =
                        (
                            (
                                (prev.get(:dist) as Lang.Number)
                                - dist
                            ).toFloat()
                            * 1000.0f
                        ) / dt.toFloat();
                    // approaching only
                    if (s > 0.0f) {
                        speedMps = s;
                    }
                }
            }

            mTrackState[trackId] = {
                :dist   => dist,
                :timeMs => nowMs
            };
            newVehicles.add([
                trackId,
                dist,
                speedMps,
                flag
            ]);
        }

        // =========================================================================
        // Fragment continuation
        // =========================================================================

        if (
            mPrevSeq != null &&
            seqByte == ((mPrevSeq + 2) & 0xFF)
        ) {
            var combined =
                mPrevVehicles.slice(null, null) as Lang.Array<Lang.Array>;
            combined.addAll(newVehicles);
            newVehicles = combined;
        }
        mPrevSeq      = seqByte;
        mPrevVehicles = newVehicles;

        // =========================================================================
        // Cleanup stale tracks
        // =========================================================================
        _pruneTrackState(newVehicles);

        // =========================================================================
        // Sort by distance ascending
        // =========================================================================
        for (var a = 1; a < newVehicles.size(); a++) {
            var key = newVehicles[a] as Lang.Array;
            var j = a - 1;
            while (
                j >= 0 &&
                (newVehicles[j] as Lang.Array)[1] > key[1]
            ) {
                newVehicles[j + 1] =
                    newVehicles[j] as Lang.Array;
                j--;
            }
            newVehicles[j + 1] = key;
        }
        vehicles = newVehicles;
        isConnected = true;
        statusStr = "BLE:ok";
    }

    // =========================================================================
    // Track cleanup
    // =========================================================================

    hidden function _pruneTrackState(currentVehicles as Lang.Array<Lang.Array>) {
        var active = {} as Lang.Dictionary<Lang.Number, Lang.Boolean>;
        for (
            var i = 0;
            i < currentVehicles.size();
            i++
        ) {
            active[
                (currentVehicles[i] as Lang.Array)[0]
            ] = true;
        }
        var keys = mTrackState.keys() as Lang.Array<Lang.Number>;
        for (
            var k = 0;
            k < keys.size();
            k++
        ) {
            if (!active.hasKey(keys[k])) {
                mTrackState.remove(keys[k]);
            }
        }
    }
}