import 'dart:async';
import 'dart:developer';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitapmate/core/di/provider/global_async_queue_provider.dart';
import 'package:vitapmate/core/di/provider/vtop_user_provider.dart';
import 'package:vitapmate/core/exceptions.dart';
import 'package:vitapmate/core/utils/entity/vtop_user_entity.dart';
import 'package:vitapmate/core/utils/featureflags/feature_flags.dart';
import 'package:vitapmate/core/utils/users/vtop_users_utils.dart';
import 'package:vitapmate/src/api/vtop/vtop_client.dart';
import 'package:vitapmate/src/api/vtop/vtop_errors.dart';
import 'package:vitapmate/src/api/vtop_get_client.dart';
part 'clinet_provider.g.dart';

@Riverpod(keepAlive: true)
class VClient extends _$VClient {
  String? _cookie;
  @override
  Future<VtopClient> build() async {
    String? username = await ref.watch(
      vtopUserProvider.selectAsync((user) => user.username),
    );
    String? password = await ref.watch(
      vtopUserProvider.selectAsync((user) => user.password),
    );
    log("Vtop client build sucessfull");
    // Future.microtask(() async {
    //   try {
    //     await tryLogin();
    //   } catch (e) {
    //     log("$e");
    //   }
    // });
    var storage = await SharedPreferences.getInstance();
    int cookieTime = storage.getInt("cookie_time") ?? 0;
    if (DateTime.now().toUtc().millisecondsSinceEpoch - cookieTime <
        30 * 60 * 1000) {
      _cookie = storage.getString("cookie");
    }

    return getVtopClient(
      username: username!,
      password: password!,
      cookie: _cookie,
    );
  }

  void replaceVClinet(VtopClient vclinet) {
    state = AsyncData(vclinet);
  }

  Future<void> tryLogin() async {
    VtopClient client = await future;
    VtopUserEntity user = await ref.watch(vtopUserProvider.future);
    if (await fetchIsAuth(client: client)) return;
    if (!user.isValid) throw VtopError.invalidCredentials();
    var gb = await ref.read(gbProvider.future);
    var feature = gb.feature("try-login");
    if (!feature.on || !feature.value) {
      throw FeatureDisabledException("Login is Disabled");
    }
    log("login try");

    try {
      await ref
          .read(globalAsyncQueueProvider.notifier)
          .run(
            "vtop_login_${user.username}",
            () => vtopClientLogin(client: client),
          );
      var newCookie =
          String.fromCharCodes(
            await fetchCookies(client: client),
          ).split(";").first.trim();
      log("past cookie ${_cookie ?? ""} and new cookie $newCookie");
      if (_cookie != newCookie) {
        var storage = await SharedPreferences.getInstance();
        await storage.setString("cookie", newCookie);
        // if (newCookie
        //     .split(";")
        //     .map((e) => e.trim())
        //     .toSet()
        //     .intersection((_cookie??"").split(";").map((e) => e.trim()).toSet())
        //     .isEmpty) {}
        await storage.setInt(
          "cookie_time",
          DateTime.now().toUtc().millisecondsSinceEpoch,
        );

        _cookie = newCookie;
      }
    } catch (e) {
      if (e == VtopError.invalidCredentials()) {
        log("password change");
        await ref
            .read(vtopusersutilsProvider.notifier)
            .vtopUserSave(user.copyWith(isValid: false));
        ref.invalidate(vtopUserProvider);
      }

      rethrow;
    }
  }
}
