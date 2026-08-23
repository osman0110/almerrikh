export 'camera_service_stub.dart'
    if (dart.library.html) 'camera_service_web.dart'
    if (dart.library.io) 'camera_service_mobile.dart';
