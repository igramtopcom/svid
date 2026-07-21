import 'package:mocktail/mocktail.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/features/downloads/data/datasources/download_local_datasource.dart';
import 'package:svid/features/downloads/data/datasources/download_native_datasource.dart';
import 'package:svid/features/downloads/data/datasources/gallerydl_datasource.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/data/remote/api/ssvid_api_service.dart';
import 'package:svid/features/downloads/domain/repositories/download_repository.dart';

class MockBackendClient extends Mock implements BackendClient {}

class MockYtDlpDataSource extends Mock implements YtDlpDataSource {}

class MockGalleryDlDataSource extends Mock implements GalleryDlDataSource {}

class MockSSvidApiService extends Mock implements SSvidApiService {}

class MockDownloadRepository extends Mock implements DownloadRepository {}

class MockDownloadLocalDataSource extends Mock implements DownloadLocalDataSource {}

class MockDownloadNativeDataSource extends Mock implements DownloadNativeDataSource {}
