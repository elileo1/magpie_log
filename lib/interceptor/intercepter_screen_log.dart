import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:magpie_log/file/log_util.dart';
import 'package:magpie_log/magpie_constants.dart';
import 'package:magpie_log/magpie_log.dart';
import 'package:magpie_log/ui/log_screen.dart';

class LogObserver<S> extends NavigatorObserver {
  @override
  void didPush(Route route, Route previousRoute) async {
    // 当调用Navigator.push时回调
    MagpieLog.instance.routeStack.add(route);
    super.didPush(route, previousRoute);
    if (!route.settings.name.startsWith("/magpie_log")) {
      await Future.delayed(Duration(milliseconds: 500));
      try {
        LogState logState =
            StoreProvider.of<S>(route.navigator.context).state as LogState;
        var json = logState.toJson();
        String actionName =
            route.settings.name != null ? route.settings.name : "";
        String pagePath = MagpieLog.instance.getCurrentPath();
        if (MagpieLog.instance.isDebug && MagpieLog.instance.isPageLogOn) {
          {
            Navigator.push(
              MagpieLog.instance.logContext,
              PageRouteBuilder(
                  opaque: false,
                  settings: RouteSettings(name: MagpieConstants.logScreen),
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      LogScreen(
                          pagePath: pagePath,
                          actionName: actionName,
                          data: logState.toJson(),
                          logType: pageType)),
            );
          }
        } else {
          MagpieLogUtil.runTimeLog(actionName, pagePath, json, type: pageType);
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    }
  }

  void didPop(Route<dynamic> route, Route<dynamic> previousRoute) {
    MagpieLog.instance.routeStack.removeLast();
  }

  @override
  void didRemove(Route route, Route previousRoute) {
    MagpieLog.instance.routeStack.removeLast();
  }

  @override
  void didReplace({Route newRoute, Route oldRoute}) {
    MagpieLog.instance.routeStack.removeLast();
    MagpieLog.instance.routeStack.add(newRoute);
  }
}
