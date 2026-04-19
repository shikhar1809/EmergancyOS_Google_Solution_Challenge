import 'text_file_download_stub.dart'
    if (dart.library.html) 'text_file_download_web.dart' as impl;

void downloadTextFile(String filename, String contents) =>
    impl.downloadTextFile(filename, contents);
