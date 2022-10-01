import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:http/http.dart' as http;
// Import package
import 'package:geolocator/geolocator.dart';
import 'package:battery_info/battery_info_plugin.dart';

// import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

//Constant name
const notificationChannelId = 'localnotification_channel_id';
const notificationChannelName = 'MOMT FOREGROUND SERVICE';

const deviceNameLSKey = 'DeviceName';
const locationWebhookUrlLSKey = 'LocationWebhookUrl';
const deviceInfoWebhookUrlLSKey = 'DeviceInfoWebhookUrl';
const incomingSmsWebhookUrlLSKey = 'IncomingSMSWebhookUrl';
const replyPhoneNumberLSKey = 'ReplyPhoneNumber';
const replyMessageLSKey = 'ReplyMessage';

const notificationId = 888;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ////flutter_background_service
  await initializeService();

  ////Work manager
  // await Workmanager().initialize(
  //     callbackDispatcher, // The top level function, aka callbackDispatcher
  //     isInDebugMode:
  //         true // If enabled it will post a notification whenever the task is running. Handy for debugging tasks
  //     );
  // await Workmanager().registerPeriodicTask(
  //   "task-background-work",
  //   "task-background-work",
  //   initialDelay: const Duration(seconds: 15),
  //   frequency: const Duration(minutes: 15),
  // );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MOMT Automation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'MOMT Automation'),
    );
  }
}

Future determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;
  String? deviceName = "";
  String locationWebhookUrl = "";
  try {
    final prefs = await SharedPreferences.getInstance();
    deviceName = prefs.getString(deviceNameLSKey);
    locationWebhookUrl = prefs.getString(locationWebhookUrlLSKey) ?? "";
    if (locationWebhookUrl == "") return;
  } catch (e) {
    if (kDebugMode) {
      print(e);
    }
  }

  // Test if location services are enabled.
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    // Location services are not enabled don't continue
    // accessing the position and request users of the
    // App to enable the location services.
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied || !serviceEnabled) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      // Permissions are denied, next time you could try
      // requesting permissions again (this is also where
      // Android's shouldShowRequestPermissionRationale
      // returned true. According to Android guidelines
      // your App should show an explanatory UI now.
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    // Permissions are denied forever, handle appropriately.
    return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.');
  }

  // When we reach here, permissions are granted and we can
  // continue accessing the position of the device.
  var res = await Geolocator.getCurrentPosition();
  var json = res.toJson();
  json.putIfAbsent('deviceName', () => {'deviceName': deviceName});

  var str = jsonEncode(json);
  if (kDebugMode) {
    print(str);
  }

  var uri = Uri.parse(locationWebhookUrl);

  await http
      .post(uri, body: str, headers: {'content-type': 'application/json'});
}

Future getBatteryInfo() async {
  Map<String, dynamic> batteryInfo = <String, dynamic>{};
  String str = "";
  String? deviceName = "";
  String deviceInfoWebhookUrl = "";
  try {
    final prefs = await SharedPreferences.getInstance();
    deviceName = prefs.getString(deviceNameLSKey);
    deviceInfoWebhookUrl = prefs.getString(deviceInfoWebhookUrlLSKey) ?? "";
    if (deviceInfoWebhookUrl == "") return;
  } catch (e) {
    if (kDebugMode) {
      print(e);
    }
  }
  if (Platform.isAndroid) {
    var androidBatteryInfo = await BatteryInfoPlugin().androidBatteryInfo;
    if (androidBatteryInfo != null) {
      batteryInfo = <String, dynamic>{
        'batteryLevel': androidBatteryInfo.batteryLevel,
        'batteryCapacity': androidBatteryInfo.batteryCapacity,
        'chargeTimeRemaining': androidBatteryInfo.chargeTimeRemaining,
        'chargingStatus': androidBatteryInfo.chargingStatus.toString(),
        'currentAverage': androidBatteryInfo.currentAverage,
        'currentNow': androidBatteryInfo.currentNow,
        'health': androidBatteryInfo.health,
        'pluggedStatus': androidBatteryInfo.pluggedStatus,
        'present': androidBatteryInfo.present,
        'remainingEnergy': androidBatteryInfo.remainingEnergy,
        'scale': androidBatteryInfo.scale,
        'technology': androidBatteryInfo.technology,
        'temperature': androidBatteryInfo.temperature,
        'voltage': androidBatteryInfo.voltage,
        'deviceName': deviceName,
      };
      str = jsonEncode(batteryInfo);
    }
  } else if (Platform.isIOS) {
    var iosBatteryInfo = await BatteryInfoPlugin().iosBatteryInfo;
    if (iosBatteryInfo != null) {
      batteryInfo = <String, dynamic>{
        'batteryLevel': iosBatteryInfo.batteryLevel,
        'chargingStatus': iosBatteryInfo.getChargingStatus.toString(),
        'deviceName': deviceName,
      };

      str = jsonEncode(batteryInfo);
    }
  }
  if (kDebugMode) {
    print(str);
  }
  var uri = Uri.parse(deviceInfoWebhookUrl);

  await http
      .post(uri, body: str, headers: {'content-type': 'application/json'});
}

onSmsRecieved(SmsMessage message) async {
  String? replyNumber;
  String? replyMessage;
  String? str;
  String deviceName = "";
  try {
    var url = "";
    try {
      final prefs = await SharedPreferences.getInstance();
      url = prefs.getString(incomingSmsWebhookUrlLSKey) ?? "";
      if (url == "") return;

      replyNumber = prefs.getString(replyPhoneNumberLSKey);
      replyMessage = prefs.getString(replyMessageLSKey);
      deviceName = prefs.getString(deviceNameLSKey) ?? "";
      var obj = {
        "id": message.id.toString(),
        "address": message.address.toString(),
        "body": message.body.toString(),
        "date": message.date.toString(),
        "dateSent": message.dateSent.toString(),
        "read": message.read.toString(),
        "seen": message.seen.toString(),
        "subject": message.subject.toString(),
        "subscriptionId": message.subscriptionId.toString(),
        "type": message.type.toString(),
        "status": message.status.toString(),
        "serviceCenterAddress": message.serviceCenterAddress.toString(),
        "deviceName": deviceName
      };
      str = jsonEncode(obj);
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
    var uri = Uri.parse(url);

    await http
        .post(uri, body: str, headers: {'content-type': 'application/json'});
  } catch (e) {
    if (kDebugMode) {
      print(e);
    }
  }

  if (replyNumber != null &&
      replyNumber != '' &&
      replyMessage != null &&
      replyMessage != '') {
    replyMessage += "From Device: $deviceName";
    Telephony.instance.sendSms(
      to: replyNumber,
      message: replyMessage,
      statusListener: (SendStatus status) {
        if (kDebugMode) {
          print(status);
        }
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _controllerWebhookUrl = TextEditingController();
  final TextEditingController _controllerDeviceInfoUrl =
      TextEditingController();
  final TextEditingController _controllerLocationUrl = TextEditingController();
  final TextEditingController _controllerDeviceName = TextEditingController();
  final TextEditingController _controllerReplyMessage = TextEditingController();
  final TextEditingController _controllerReplyNumber = TextEditingController();
  bool _isTextFieldEnable = false;
  String _webhookUrl = "";
  String _deviceInfoUrl = "";
  String _locationInfoUrl = "";
  String _replyMessage = "";
  String _replyNumber = "";
  String _deviceName = "";

  @override
  void initState() {
    super.initState();
    // You should make sure call to instance is made every time
    // app comes to foreground
    Telephony.instance.requestPhoneAndSmsPermissions.then((value) {
      if (value == true) {
        Telephony.instance.listenIncomingSms(
          onNewMessage: onSmsRecieved,
          onBackgroundMessage: onSmsRecieved,
          listenInBackground: true,
        );
      }
      Geolocator.requestPermission().then((value) {
        if (kDebugMode) {
          print("Geolocator Permission:$value");
        }
      });
    });

    SharedPreferences.getInstance().then((prefs) {
      var url = prefs.getString(incomingSmsWebhookUrlLSKey);
      var deviceInfoUrl = prefs.getString(deviceInfoWebhookUrlLSKey);
      var locationInfoUrl = prefs.getString(incomingSmsWebhookUrlLSKey);
      var replyNumber = prefs.getString(replyPhoneNumberLSKey);
      var replyMessage = prefs.getString(replyMessageLSKey);
      var deviceName = prefs.getString(deviceNameLSKey);

      _controllerWebhookUrl.value = TextEditingValue(text: url ?? "");
      _controllerDeviceInfoUrl.value =
          TextEditingValue(text: deviceInfoUrl ?? "");
      _controllerLocationUrl.value =
          TextEditingValue(text: locationInfoUrl ?? "");
      _controllerReplyNumber.value = TextEditingValue(text: replyNumber ?? "");
      _controllerReplyMessage.value =
          TextEditingValue(text: replyMessage ?? "");
      _controllerDeviceName.value = TextEditingValue(text: deviceName ?? "");
      setState(() {
        _webhookUrl = url ?? "";
        _replyMessage = replyMessage ?? "";
        _replyNumber = replyNumber ?? "";
        _deviceName = deviceName ?? "";
        _locationInfoUrl = locationInfoUrl ?? "";
        _deviceInfoUrl = deviceInfoUrl ?? "";
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 50),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 10),
                  Column(
                    children: [
                      Row(
                        children: const [
                          Text(
                            "MOMT",
                            style: TextStyle(
                              fontSize: 34,
                              fontFamily: "Rubik Medium",
                              color: Color(0xff333333),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        "Automation",
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: "Rubik Medium",
                          color: Color(0xFFffce05),
                        ),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20),
                child: TextFormField(
                  minLines: 1,
                  maxLines: 5,
                  controller: _controllerDeviceName,
                  enabled: _isTextFieldEnable ? true : false,
                  onChanged: (value) {
                    value = value.trim();
                    setState(() {
                      _deviceName = value;
                    });
                  },
                  decoration: InputDecoration(
                      hintText: "Device Name",
                      fillColor: const Color(0xfff8f9f9),
                      filled: true,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.phone_android,
                        color: Color(0xff323f4b),
                      )),
                ),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20),
                child: TextFormField(
                  minLines: 1,
                  maxLines: 5,
                  controller: _controllerWebhookUrl,
                  enabled: _isTextFieldEnable ? true : false,
                  onChanged: (value) {
                    value = value.trim();
                    setState(() {
                      _webhookUrl = value;
                    });
                  },
                  decoration: InputDecoration(
                      hintText: "Webhook Url",
                      fillColor: const Color(0xfff8f9f9),
                      filled: true,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.link,
                        color: Color(0xff323f4b),
                      )),
                ),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20),
                child: TextFormField(
                  minLines: 1,
                  maxLines: 5,
                  controller: _controllerDeviceInfoUrl,
                  enabled: _isTextFieldEnable ? true : false,
                  onChanged: (value) {
                    value = value.trim();
                    setState(() {
                      _deviceInfoUrl = value;
                    });
                  },
                  decoration: InputDecoration(
                      hintText: "Device status webhook Url",
                      fillColor: const Color(0xfff8f9f9),
                      filled: true,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.link,
                        color: Color(0xff323f4b),
                      )),
                ),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20),
                child: TextFormField(
                  minLines: 1,
                  maxLines: 5,
                  controller: _controllerLocationUrl,
                  enabled: _isTextFieldEnable ? true : false,
                  onChanged: (value) {
                    value = value.trim();
                    setState(() {
                      _locationInfoUrl = value;
                    });
                  },
                  decoration: InputDecoration(
                      hintText: "Location Webhook Url",
                      fillColor: const Color(0xfff8f9f9),
                      filled: true,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.link,
                        color: Color(0xff323f4b),
                      )),
                ),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20),
                child: TextFormField(
                  controller: _controllerReplyNumber,
                  enabled: _isTextFieldEnable ? true : false,
                  onChanged: (value) {
                    value = value.trim();
                    setState(() {
                      _replyNumber = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: "Mobile Number",
                    fillColor: const Color(0xfff8f9f9),
                    filled: true,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                        color: Color(0xffe4e7eb),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                        color: Color(0xffe4e7eb),
                      ),
                    ),
                    prefixIcon: const Icon(
                      Icons.phone_rounded,
                      color: Color(0xff323f4b),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20),
                child: TextFormField(
                  controller: _controllerReplyMessage,
                  enabled: _isTextFieldEnable ? true : false,
                  minLines: 1,
                  maxLines: 15,
                  onChanged: (value) {
                    value = value.trim();
                    setState(() {
                      _replyMessage = value;
                    });
                  },
                  decoration: InputDecoration(
                      hintText: "Message",
                      fillColor: const Color(0xfff8f9f9),
                      filled: true,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xffe4e7eb),
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.message,
                        color: Color(0xff323f4b),
                      )),
                ),
              ),
              const SizedBox(height: 50),
              InkWell(
                onTap: () {
                  if (_isTextFieldEnable) {
                    SharedPreferences.getInstance().then((prefs) {
                      prefs.setString(incomingSmsWebhookUrlLSKey, _webhookUrl);
                      prefs.setString(replyPhoneNumberLSKey, _replyNumber);
                      prefs.setString(replyMessageLSKey, _replyMessage);
                      prefs.setString(deviceNameLSKey, _deviceName);
                      prefs.setString(
                          locationWebhookUrlLSKey, _locationInfoUrl);
                      prefs.setString(
                          deviceInfoWebhookUrlLSKey, _deviceInfoUrl);
                    });
                  }
                  setState(() {
                    _isTextFieldEnable = !_isTextFieldEnable;
                  });
                },
                child: Container(
                  height: 50,
                  width: 300,
                  decoration: BoxDecoration(
                      color: const Color(0xFFffce05),
                      borderRadius: BorderRadius.circular(10)),
                  child: Center(
                    child: Text(
                      _isTextFieldEnable ? "Save" : "Edit",
                      style: const TextStyle(
                        fontSize: 18,
                        fontFamily: "Rubik Regular",
                        color: Color(0xff333333),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//Background service

// this will be used for notification id, So you can update your custom notification with this id.

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  /// OPTIONAL, using custom notification channel id
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    notificationChannelName, // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // if (Platform.isIOS) {
  //   await flutterLocalNotificationsPlugin.initialize(
  //     const InitializationSettings(
  //       iOS: IOSInitializationSettings(),
  //     ),
  //   );
  // }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: true,

      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'MOMT SERVICE',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,

      // you have to enable background fetch capability on xcode project
      onBackground: onIosBackground,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final log = preferences.getStringList('log') ?? <String>[];
  log.add(DateTime.now().toIso8601String());
  await preferences.setStringList('log', log);

  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  // For flutter prior to version 3.0.0
  // We have to register the plugin manually

  if (kDebugMode) {
    print('FLUTTER BACKGROUND SERVICE: ${DateTime.now()}');
  }

  /// OPTIONAL when use custom notification
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // bring to foreground
  Timer.periodic(const Duration(seconds: 60), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        /// OPTIONAL for use custom notification
        /// the notification id must be equals with AndroidConfiguration when you call configure() method.
        flutterLocalNotificationsPlugin.show(
          notificationId,
          'MOMT Automation App running',
          // ' ${DateTime.now()}',
          '',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              notificationChannelId,
              notificationChannelName,
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );

        // if you don't using custom notification, uncomment this
        // service.setForegroundNotificationInfo(
        //   title: "My App Service",
        //   content: "Updated at ${DateTime.now()}",
        // );
      }
    }

    getBatteryInfo();
    determinePosition();

    // Telephony.instance.requestPhoneAndSmsPermissions.then((value) {
    //   if (value == true) {
    //     Telephony.instance.listenIncomingSms(
    //       onNewMessage: onSmsRecieved,
    //       onBackgroundMessage: onSmsRecieved,
    //       listenInBackground: true,
    //     );
    //   }
    // });

    /// you can see this log in logcat
    // print('FLUTTER BACKGROUND SERVICE: ${DateTime.now()}');

    // test using external plugin
    // final deviceInfo = DeviceInfoPlugin();
    // String? device;
    // if (Platform.isAndroid) {
    //   final androidInfo = await deviceInfo.androidInfo;
    //   device = androidInfo.model;
    // }

    // if (Platform.isIOS) {
    //   final iosInfo = await deviceInfo.iosInfo;
    //   device = iosInfo.model;
    // }

    service.invoke(
      'update',
      {
        "current_date": DateTime.now().toIso8601String(),
        "device": 'android mobile ',
      },
    );
  });
}
