import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info/device_info.dart';
import 'package:flutter/services.dart';
import 'package:magpie_log/file/data_analysis.dart';
import 'package:magpie_log/file/data_statistics.dart';
import 'package:magpie_log/file/file_utils.dart';
import 'package:magpie_log/model/analysis_model.dart';

import '../file/data_statistics.dart';
import '../magpie_log.dart';
import '../model/device_data.dart';

///已圈选数据统计上报

class MagpieStatisticsHandler {
  final String _tag = 'MagpieStatisticsHandler';

  factory MagpieStatisticsHandler() => _getInstance();

  static MagpieStatisticsHandler get instance => _getInstance();

  static MagpieStatisticsHandler _instance;

  static MagpieStatisticsHandler _getInstance() {
    if (_instance == null) {
      _instance = MagpieStatisticsHandler._init();
    }

    return _instance;
  }

  int _time, _count;

  ReportChannel _reportChannel;

  ReportMethod _reportMethod;

  get reportChannel => _reportChannel;

  get reportMethod => _reportMethod;

  void setReportChannel(ReportChannel channelType) {
    _reportChannel = channelType;
    print('ReportChannel value = $_reportChannel');
  }

  void setReportMethod(ReportMethod method) {
    this._reportMethod = method;
  }

  Timer _timer;

  List<Map<String, dynamic>> _dataStatistics;

  MagpieStatisticsHandler._init() {
    _dataStatistics = List();
  }

  /**
   * 初始化配置。
   *  [reportMethod]    数据上报方式，默认单条上报
   *  [reportChannel]   数据上报通道，默认Flutter
   *  [time]            定时上报方式需要设置的时间周期。默认为2*60*1000ms
   *  [count]           计数上报方式需要设置的采集数量。默认为50条
   *  [callback]        设置Flutter通信的callback。如果数据上报通过flutter实现，此方法必须实现！！！
   */
  void initConfig(ReportMethod reportMethod, ReportChannel reportChannel,
      {int time: 2 * 60 * 1000,
      int count: 50,
      AnalysisCallback callback}) async {
    this._count = count;
    this._time = time;
    this._reportMethod = reportMethod;
    this._reportChannel = reportChannel;
    _MagpieAnalysisHandler.instance.initHandler(reportChannel, callback);
    print(
        '$_tag initConfig, reportMethod = $_reportMethod,reportChannel = $_reportChannel');

    //返回公共参数。原则上初始化的时候需要上报一次，但是不强制
    String _deviceInfo = (await _createCommonParams()).toJson().toString();

    ///初始化时判断是否有之前写入的未上报数据，有则上报后删除
    if (await MagpieDataStatistics.isExistsStatistics()) {
      await MagpieDataStatistics.writeStatisticsData(
          {'deviceInfo': _deviceInfo});

      _MagpieAnalysisHandler.instance
          .sendDataToJson(await MagpieDataStatistics.readStatisticsData());
      MagpieDataStatistics.clearStatisticsData();
    } else {
      _MagpieAnalysisHandler.instance
          .sendDataToMap({'deviceInfo': _deviceInfo});
    }
  }

  ///写入要上报的圈选数据
  void writeData(Map<String, dynamic> data) {
    if (_reportMethod != ReportMethod.each) {
      _saveData(data);
    }
    if (_reportMethod == ReportMethod.timing) {
      if (_timer == null) {
        _reportDataToTimer();
      }
    } else if (_reportMethod == ReportMethod.total) {
      _reportDataToCount(data);
    } else {
      _MagpieAnalysisHandler.instance.sendDataToMap(data);
    }
  }

  /// app退出时调用
  void exitMagpie() {
    if (_timer.isActive) {
      _timer.cancel();
      _timer = null;
    }
  }

  void _saveData(Map<String, dynamic> data) async {
    if (data != null && data.isNotEmpty) {
      _dataStatistics.add(data);
    }
    if (await MagpieDataStatistics.isExistsStatistics()) {
      MagpieDataStatistics.writeStatisticsData(data);
    } else {
      MagpieDataStatistics.writeStatisticsData({'data': _dataStatistics});
    }
  }

  //定时上报
  void _reportDataToTimer() {
    _timer = Timer.periodic(Duration(milliseconds: _time), (method) async {
      if (_dataStatistics.isNotEmpty ||
          await MagpieDataStatistics.isExistsStatistics()) {
        var data;
        if (_dataStatistics.isEmpty) {
          data = await MagpieDataStatistics.readStatisticsData();
        } else {
          var params = {'data': _dataStatistics};
          data = jsonEncode(params).toString();
        }
        _sendData(data);
      }
    });
  }

  //计数上报
  void _reportDataToCount(Map<String, dynamic> data) async {
    if (_dataStatistics.length >= _count) {
      var params = {'data': _dataStatistics};
      String jsonData = jsonEncode(params).toString();

      _sendData(jsonData);
    }
  }

  void _sendData(String jsonData) async {
    _MagpieAnalysisHandler.instance.sendDataToJson(jsonData);
    _dataStatistics.clear();
    await MagpieDataStatistics.clearStatisticsData();
  }

  ///构造公共参数
  Future<DeviceData> _createCommonParams() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    var platform, deviceVersion, clientId, deviceName, deviceId, model;
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      platform = 'Android';
      deviceVersion = androidInfo.version.release;
      deviceName = androidInfo.brand;
      model = androidInfo.model;
      deviceId = androidInfo.androidId;
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      platform = "iOS";
      deviceVersion = iosInfo.systemVersion;
      deviceName = iosInfo.name;
      model = iosInfo.model;
      deviceId = iosInfo.identifierForVendor;
    }
    clientId = globalClientId;

    DeviceData info = DeviceData(
        platform, clientId, deviceName, deviceId, deviceVersion, model);

    print('$_tag createCommonParams Android device Info =  ${info.toJson()}');

    return info;
  }
}

///非单条上报时，每次数据add到list中时，一并写入到文件中
///数据上报优先以文件数据为准
///上报后清空内存缓存和文件

typedef AnalysisCallback = Function(String jsonData);

class _MagpieAnalysisHandler {
  static final String _tag = 'AnalysisHandler';

  static final String _channelName = 'magpie_analysis_channel';

  //上报圈选数据通道类型，0 - Flutter，1 - Native
  ReportChannel _channelType;

  factory _MagpieAnalysisHandler() => _getInstance();

  static _MagpieAnalysisHandler get instance => _getInstance();

  static _MagpieAnalysisHandler _instance;

  var _msgChannel;

  AnalysisCallback _callback;

  //发送圈选数据
  void sendDataToMap(Map<String, dynamic> data) {
    if (data == null || data.isEmpty) {
      print('$_tag sendData data 不合法！！！');
      return;
    }

    sendDataToJson(jsonEncode(data).toString());
  }

  void sendDataToJson(String jsonData) {
    if (jsonData.isNotEmpty) {
      if (_channelType == ReportChannel.natives) {
        _MagpieAnalysisHandler.instance._sendMsgToNative(jsonData);
      } else {
        _MagpieAnalysisHandler.instance._sendMsgToFlutter(jsonData);
      }
      print('$_tag sendDataToJson jsonData = $jsonData');
    }
  }

  //设置Flutter通信的callback。如果数据上报通过flutter实现，此方法必须实现！！！
  void initHandler(ReportChannel channelType, AnalysisCallback callback) {
    this._channelType = channelType;
    if (channelType != ReportChannel.natives) {
      this._callback = callback;
    }
  }

  _MagpieAnalysisHandler._handler() {
    _msgChannel = BasicMessageChannel(_channelName, StringCodec());
  }

  static _MagpieAnalysisHandler _getInstance() {
    if (_instance == null) {
      _instance = _MagpieAnalysisHandler._handler();
    }
    return _instance;
  }

  Future<Null> _sendMagpieData(String data) async {
    await _msgChannel.send(data);
  }

  //通过callback发送数据给Flutter
  void _sendMsgToFlutter(String data) {
    if (_callback == null) {
      print('$_tag callback is null');
      return;
    }
    _callback(data);
  }

  //通过BasicMessageChannel发送数据给Native
  void _sendMsgToNative(String data) {
    _sendMagpieData(data);
    print('$_tag sendMsgToNative : ${jsonEncode(data).toString()}');
  }
}
