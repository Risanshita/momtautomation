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
import 'package:workmanager/workmanager.dart';

// import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (kDebugMode) {
      print("Task EXECUTED");
    }
    int? totalExecutions;
    final sharedPreference =
        await SharedPreferences.getInstance(); //Initialize dependency

    try {
      //add code execution
      totalExecutions = sharedPreference.getInt("totalExecutions");
      sharedPreference.setInt(
          "totalExecutions", totalExecutions == null ? 1 : totalExecutions + 1);
      if (kDebugMode) {
        print("TotalExecutoin $totalExecutions");
      }
    } catch (err) {
      if (kDebugMode) {
        print(err.toString());
      }
    }

    return Future.value(true);
  });
}

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
    deviceName = prefs.getString('DeviceName');
    locationWebhookUrl = prefs.getString('LocationWebhookUrl') ?? "";
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
  if (permission == LocationPermission.denied) {
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

  await http.post(uri, body: str);
}

Future getBatteryInfo() async {
  Map<String, dynamic> batteryInfo = <String, dynamic>{};
  String str = "";
  String? deviceName = "";
  String deviceInfoWebhookUrl = "";
  try {
    final prefs = await SharedPreferences.getInstance();
    deviceName = prefs.getString('DeviceName');
    deviceInfoWebhookUrl = prefs.getString('DeviceInfoWebhookUrl') ?? "";
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

  await http.post(uri, body: str);
}

onSmsRecieved(SmsMessage message) async {
  String? replyNumber;
  String? replyMessage;
  String? str;
  try {
    var url = "";
    try {
      final prefs = await SharedPreferences.getInstance();
      url = prefs.getString('WebhookUrl') ?? "";
      if (url == "") return;

      replyNumber = prefs.getString('ReplyNumber');
      replyMessage = prefs.getString('ReplyMessage');
      var deviceName = prefs.getString('DeviceName');
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

    await http.post(uri, body: str);
  } catch (e) {
    if (kDebugMode) {
      print(e);
    }
  }

  if (replyNumber != null &&
      replyNumber != '' &&
      replyMessage != null &&
      replyMessage != '') {
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
  int? _totalExecutions;
  final telephony = Telephony.instance;

  @override
  void initState() {
    super.initState();
    // You should make sure call to instance is made every time
    // app comes to foreground

    telephony.requestPhoneAndSmsPermissions.then((value) {
      if (value == true) {
        telephony.listenIncomingSms(
          onNewMessage: onSmsRecieved,
          onBackgroundMessage: onSmsRecieved,
          listenInBackground: true,
        );
      }
    });
    SharedPreferences.getInstance().then((prefs) {
      var url = prefs.getString('WebhookUrl');
      var deviceInfoUrl = prefs.getString('DeviceInfoUrl');
      var locationInfoUrl = prefs.getString('LocationInfoUrl');
      var replyNumber = prefs.getString('ReplyNumber');
      var replyMessage = prefs.getString('ReplyMessage');
      var deviceName = prefs.getString('DeviceName');

      setState(() {
        _totalExecutions = prefs.getInt("totalExecutions");
      });
      _controllerWebhookUrl.value = TextEditingValue(text: url ?? "");
      _controllerDeviceInfoUrl.value =
          TextEditingValue(text: deviceInfoUrl ?? "");
      _controllerLocationUrl.value =
          TextEditingValue(text: locationInfoUrl ?? "");
      _controllerReplyNumber.value = TextEditingValue(text: replyNumber ?? "");
      _controllerReplyMessage.value =
          TextEditingValue(text: replyMessage ?? "");

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

  // getApiData() async {
  //   try {
  //     var uri = Uri.parse("http://10.0.2.2:5224/api/weatherforecast");
  //     var response = await http.get(uri);
  //     var data = response.body;

  //     var res = json.decode(response.body);
  //     var ob = (res as Iterable<dynamic>)
  //         .map(
  //           (dynamic jsonObject) =>
  //               WeatherForecast.fromMap(jsonObject as Map<String, dynamic>),
  //         )
  //         .toList();
  //     print(ob);
  //   } catch (e) {
  //     print(e);
  //   }
  // }

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
                      Text(
                        ("Message received: ${_totalExecutions ?? 0}"),
                        style: const TextStyle(
                          fontSize: 24,
                          fontFamily: "Rubik Medium",
                          color: Color(0xff333333),
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
                      hintText: "Locatino Webhook Url",
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
                      prefs.setString('WebhookUrl', _webhookUrl);
                      prefs.setString('ReplyNumber', _replyNumber);
                      prefs.setString('ReplyMessage', _replyMessage);
                      prefs.setString('DeviceName', _deviceName);
                      prefs.setString('LocationWebhookUrl', _locationInfoUrl);
                      prefs.setString('DeviceInfoWebhookUrl', _deviceInfoUrl);
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

const notificationChannelId = 'localnotification_channel_id';
const notificationChannelName = 'MOMT FOREGROUND SERVICE';

// this will be used for notification id, So you can update your custom notification with this id.
const notificationId = 888;

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
      initialNotificationTitle: 'AWESOME SERVICE',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
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
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        /// OPTIONAL for use custom notification
        /// the notification id must be equals with AndroidConfiguration when you call configure() method.
        flutterLocalNotificationsPlugin.show(
          888,
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
