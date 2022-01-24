import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_nordic_dfu/flutter_nordic_dfu.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  FlutterBlue flutterBlue = FlutterBlue.instance;
  StreamSubscription<ScanResult>? scanSubscription;
  List<ScanResult> scanResults = <ScanResult>[];
  List<BluetoothService> _services = [];
  DateTime _now = DateTime.now();
  bool dfuRunning = false;
  int? dfuRunningInx;

  @override
  void initState() {
    Timer.periodic(
        const Duration(milliseconds: 500),
        (Timer t) => setState(() {
              _now = DateTime.now();
            }));

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isScan = scanSubscription != null;

    return MaterialApp(
      title: "lock DFU & Sync:",
      theme: ThemeData(
          primarySwatch: Colors.teal, textTheme: GoogleFonts.robotoTextTheme()),
      home: Scaffold(
        appBar: AppBar(
          title: Container(
            child: Column(
              children: [
                Text(
                  "${_now.year.toString()}-${_now.month.toString().padLeft(2, '0')}-${_now.day.toString().padLeft(2, '0')} ${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}",
                ),
              ],
            ),
            alignment: Alignment.center,
          ),
        ),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              child: ElevatedButton(
                child: Icon(
                  isScan ? Icons.pause : Icons.play_arrow,
                  size: 50,
                ),
                onPressed: dfuRunning ? null : (isScan ? stopScan : startScan),
              ),
            ),
            Expanded(
              child: scanResults.isEmpty
                  ? const Center(child: Text('No Device'))
                  : ListView.builder(
                      itemCount: scanResults.length,
                      itemBuilder: (context, int index) {
                        return DeviceItem(
                          isRunningItem: dfuRunningInx == null
                              ? false
                              : dfuRunningInx == index,
                          scanResult: scanResults[index],
                          onDFU: dfuRunning
                              ? () async {
                                  await FlutterNordicDfu.abortDfu();
                                  setState(() {
                                    dfuRunningInx = null;
                                  });
                                }
                              : () async {
                                  setState(() => dfuRunningInx = index);
                                  await doDfu(scanResults[index].device.id.id);
                                  setState(() => dfuRunningInx = null);
                                  stopScan();
                                  startScan();
                                },
                          onSync: () async {
                            try {
                              await scanResults[index].device.connect();
                            } finally {
                              _services = await scanResults[index]
                                  .device
                                  .discoverServices();
                            }
                            await _synchronizeTimeDir();
                            await scanResults[index].device.disconnect();
                          },
                        );
                      },
                    ),
            ),
            Container(
              decoration: const BoxDecoration(
                  color: Colors.teal,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10))),
              alignment: Alignment.center,
              width: double.infinity,
              height: 25,
              child: const Text(
                'Created by Michal Valkoun',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> doDfu(String deviceId) async {
    stopScan();
    dfuRunning = true;
    try {
      await FlutterNordicDfu.startDfu(deviceId, 'assets/1.8.zip',
          fileInAsset: true);
      dfuRunning = false;
    } catch (e) {
      dfuRunning = false;
    }
  }

  void startScan() async {
    scanSubscription?.cancel();
    await flutterBlue.stopScan();
    setState(
      () {
        scanResults.clear();
        scanSubscription = flutterBlue.scan().listen(
              (result) => setState(
                () {
                  if (result.device.name == 'Nixie Clock BL' ||
                      result.device.name == 'Nixie Clock') {
                    scanResults.add(result);
                    scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
                  }
                },
              ),
            );
      },
    );
  }

  void stopScan() {
    scanSubscription?.cancel();
    setState(() => scanSubscription = null);
  }

  _synchronizeTimeDir() async {
    _now = DateTime.now();
    int timestamp = (_now.millisecondsSinceEpoch / 1000 + 3600).round();
    await _services
        .firstWhere((service) => service.uuid.toString().contains('a8ed1400'))
        .characteristics[7]
        .write([
      timestamp & 0xFF,
      (timestamp >> 8) & 0xFF,
      (timestamp >> 16) & 0xFF,
      (timestamp >> 24) & 0xFF
    ]);
  }
}

class DeviceItem extends StatelessWidget {
  final ScanResult scanResult;

  final VoidCallback onDFU;

  final VoidCallback onSync;

  final bool isRunningItem;

  const DeviceItem({
    Key? key,
    required this.scanResult,
    required this.onDFU,
    required this.onSync,
    required this.isRunningItem,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scanResult.device.name),
                Text(scanResult.device.id.id),
                Text("RSSI: ${scanResult.rssi}"),
              ],
            ),
          ),
          scanResult.device.name.contains('BL')
              ? Button(
                  onPressed: onDFU,
                  color: Colors.green,
                  text: isRunningItem ? "Abort DFU" : "Start DFU",
                )
              : Button(
                  onPressed: onSync,
                  color: Colors.blue,
                  text: "Sync Time",
                ),
        ],
      ),
    );
  }
}

class Button extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;
  final Color color;
  const Button({
    Key? key,
    required this.onPressed,
    required this.text,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                  topRight: Radius.circular(5),
                  bottomRight: Radius.circular(5))),
          padding: const EdgeInsets.only(top: 20, bottom: 20),
          backgroundColor: color,
          primary: Colors.white,
        ),
        child: Text(text, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
