import 'dart:convert';
import 'dart:io';

import 'package:device_info/device_info.dart';
import 'package:flutter/material.dart';
import 'package:magpie_log/file/file_utils.dart';
import 'package:magpie_log/handler/statistics_handler.dart';
import 'package:magpie_log/model/analysis_model.dart';
import 'package:magpie_log/model/device_data.dart';

import '../magpie_log.dart';

///数据分析配置文件操作
class MagpieDataAnalysis {
  static final String _tag = 'Magpie Data Analysis';

  static final String _dirName = 'data_analysis';

  ///数据分析配置参数统一写到统一文件中，所以在此直接定义好文件名称
  static final String _fileName = 'analysis.json';

  static final List<AnalysisModel> _listData = List();

  /// 初始化接口
  static void initMagpieData(BuildContext context) async {
    var data;
    //圈选数据以文件中的为准，只有首次的时候从assets下读取并copy到内存中
    //动态下发的埋点数据需要全部写入到文件中
    if (await MagpieFileUtils.isExistsFile(
        fileName: _fileName, dirName: _dirName)) {
      data = await MagpieFileUtils.readFile(
          fileName: _fileName, dirName: _dirName);
    } else {
      //原则上assets目录中的配置文件只会读取一次
      data = await DefaultAssetBundle.of(context)
          .loadString('assets/analysis.json');
    }

    if (_listData.isEmpty) {
      if (data.isNotEmpty) {
        Map<String, dynamic> analysis = jsonDecode(data);
        AnalysisData analysisData = AnalysisData.fromJson(analysis);
        _listData.addAll(analysisData.data);
        print(
            '$_tag initMagpieData, ${analysisData.reportChannel} , ${analysisData.reportMethod}');
      }
    }
  }

  static Future<Null> saveData() async {
    if (_listData.isEmpty) {
      print('$_tag saveData error!!! _listData is empty...');
      return;
    }
    //判断是否有之前写入的文件,有则删除
    await MagpieFileUtils.rmFile(fileName: _fileName, dirName: _dirName);

    await MagpieFileUtils.writeFile(
        fileName: _fileName,
        contents: jsonEncode(AnalysisData(
                _listData,
                MagpieStatisticsHandler.instance.reportChannel,
                MagpieStatisticsHandler.instance.reportMethod)
            .toJson()),
        dirName: _dirName);
  }

  static Future<Null> writeData(AnalysisModel analysisModel) async {
    if (analysisModel == null ||
        analysisModel.actionName.isEmpty ||
        analysisModel.pagePath.isEmpty ||
        analysisModel.analysisData.isEmpty) {
      print('$_tag writeData error!!! 请再次检查AnalysisModel！！！ ');
      return;
    }

    if (_listData.isEmpty) {
      //首次添加先获取全量数据
      String analysisData = await readFileData();
      if (analysisData.isNotEmpty) {
        Map<String, dynamic> analysis = jsonDecode(analysisData);
        AnalysisData data = AnalysisData.fromJson(analysis);
        _listData.addAll(data.data);
        print('$_tag writeData addAll list length = ${_listData.length}');
      }
    }
    //数据去重
    if (_listData.any((item) => item.actionName == analysisModel.actionName)) {
      print(
          '$_tag writeData list replace data, action = ${analysisModel.toString()} ');
      for (var item in _listData) {
        if (item.actionName == analysisModel.actionName &&
            item.pagePath == analysisModel.pagePath) {
          _listData.remove(item);
          _listData.add(analysisModel);
          print(
              '$_tag writeData list replace data, action = ${analysisModel.actionName}} : pagePath = ${analysisModel.pagePath} : data = ${item.analysisData}');
        }
      }
    } else {
      print('$_tag writeData list add data');
      _listData.add(analysisModel);
    }

    print(
        '$_tag writeData list length = ${_listData.length}, action = ${analysisModel.actionName} : pagePath = ${analysisModel.pagePath} : data = ${analysisModel.analysisData}');
  }

  ///完整的圈选数据读取
  static Future<String> readFileData() async {
    try {
      return jsonEncode(AnalysisData(
          _listData,
          MagpieStatisticsHandler.instance.reportChannel,
          MagpieStatisticsHandler.instance.reportMethod));
    } catch (e) {
      print('$_tag : readFile error = $e');
    }
    return '';
  }

  ///获取已选择的圈选数据集合
  static List<AnalysisModel> getListData() => _listData;

  ///根据圈选埋点的action，读取指定数据。[action] 圈选埋点的key。
  static Future<AnalysisModel> readActionData(
      {@required String actionName,
      @required String pagePath,
      String type}) async {
    if (_listData.isEmpty) {
      print('$_tag readActionData listData isEmpty！！！');
      return null;
    } else if (actionName.isEmpty || pagePath.isEmpty) {
      print('$_tag readActionData 请检查传入参数是否正确！！！');
      return null;
    } else {
      // if (_listData.any((item) =>
      //     item.actionName == actionName && item.pagePath == pagePath)) {

      List<AnalysisModel> modelList = [];

      for (var item in _listData) {
        print(
            '$_tag readActionData actionName = ${item.actionName} , pagePath = ${item.pagePath} ,data = ${item.analysisData}');
        if (item.actionName == actionName && item.pagePath == pagePath) {
          print(
              '$_tag readActionData select actionName = ${item.actionName} , pagePath = ${item.pagePath} ,data = ${item.analysisData}');
          modelList.add(item);
        }
      }

      if (null != type) {
        for (var item in modelList) {
          if (item.type == type) {
            return item;
          }
        }
      } else if (modelList.length > 0) {
        return modelList[0];
      }

      // }
      print(
          '$_tag readActionData listData none , actionName = $actionName , pagePath = $pagePath');
      return null;
    }
  }

  ///获取文件路径
  static Future<String> getSavePath() async {
    return await MagpieFileUtils.getFilePath(
        fileName: _fileName, dirName: _dirName);
  }

  ///清除全部数据。直接删除文件就完了呀呀呀呀呀
  static Future<Null> clearAnalysisData() async {
    _listData.clear();
    MagpieFileUtils.clearFileData(fileName: _fileName, dirName: _dirName);
    print('$_tag clearAnalysisData _listData.length = ${_listData.length}');
  }

  static Future<int> deleteActionData({@required String actionName}) async {
    if (actionName.isEmpty) {
      print('$_tag deleteActionData actionName isEmpty');
      return -1;
    }

    if (_listData.isEmpty) {
      print('$_tag deleteActionData listData isEmpty');
      return -3;
    }
    if (_listData.any((item) => item.actionName == actionName)) {
      for (var item in _listData) {
        if (item.actionName == actionName) {
          _listData.remove(item);

          print(
              '$_tag deleteActionData remove actionName = ${item.actionName}');
          return 0;
        }
      }
    }

    return -2;
  }
}
