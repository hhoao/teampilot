import 'dart:io';

import 'package:teampilot/services/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('cliProjectBucketForPrimaryPath matches CLI projects layout', () {
    expect(
      AppStorage.cliProjectBucketForPrimaryPath('/home/hhoa/agent'),
      '-home-hhoa-agent',
    );
    expect(AppStorage.cliProjectBucketForPrimaryPath(''), '');
  });

  test('cliSessionDescriptorExists finds jsonl under projects bucket', () async {
    final tmp = await Directory.systemTemp.createTemp('fsai_cli_root_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const uuid = '2b5f4dec-9534-4960-b967-fd492e272cec';
    final bucket = p.join(tmp.path, 'projects', '-home-hhoa-agent');
    await Directory(bucket).create(recursive: true);
    await File(p.join(bucket, '$uuid.jsonl')).writeAsString('');

    expect(
      AppStorage.cliSessionDescriptorExists(
        uuid,
        '/home/hhoa/agent',
        dataRoot: tmp.path,
      ),
      isTrue,
    );
  });

  test('cliSessionDescriptorExists finds sessions json', () async {
    final tmp = await Directory.systemTemp.createTemp('fsai_cli_root_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const uuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await Directory(p.join(tmp.path, 'sessions')).create(recursive: true);
    await File(p.join(tmp.path, 'sessions', '$uuid.json')).writeAsString('{}');

    expect(
      AppStorage.cliSessionDescriptorExists(uuid, '', dataRoot: tmp.path),
      isTrue,
    );
  });

  test('cliSessionDescriptorExists scans projects when slug mismatches', () async {
    final tmp = await Directory.systemTemp.createTemp('fsai_cli_root_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const uuid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    final bucket = p.join(tmp.path, 'projects', 'custom-bucket-name');
    await Directory(bucket).create(recursive: true);
    await File(p.join(bucket, '$uuid.jsonl')).writeAsString('');

    expect(
      AppStorage.cliSessionDescriptorExists(
        uuid,
        '/wrong/path',
        dataRoot: tmp.path,
      ),
      isTrue,
    );
  });

  test('cliSessionDescriptorExists finds session directory under bucket', () async {
    final tmp = await Directory.systemTemp.createTemp('fsai_cli_root_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const uuid = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    final bucket = p.join(tmp.path, 'projects', '-tmp-work');
    await Directory(p.join(bucket, uuid)).create(recursive: true);

    expect(
      AppStorage.cliSessionDescriptorExists(
        uuid,
        '/tmp/work',
        dataRoot: tmp.path,
      ),
      isTrue,
    );
  });
}
