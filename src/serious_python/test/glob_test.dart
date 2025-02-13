import 'package:flutter_test/flutter_test.dart';
import 'package:glob/glob.dart';

void main() {
  test("test globs", () async {
    final dartFile = Glob("**.dart");
    expect(dartFile.matches("a\\b\\c\\something.dart"), true);
    expect(dartFile.matches("a/something.dart/sub-dir"), false);

    final distInfo = Glob("**.dist-info");
    expect(distInfo.matches("lru_dict-1.3.0.dist-info"), true);
    expect(distInfo.matches("a/b/lru_dict-1.3.0.dist-info"), true);
    expect(distInfo.matches("lru_dict-1.3.0.dist-info/METADATA"), false);

    final pyCache = Glob("**\\__pycache__");
    expect(pyCache.matches("a/b/__pycache__"), true);
    expect(pyCache.matches("a\\__pycache__"), true);
    expect(pyCache.matches("__pycache__"), true);
    expect(pyCache.matches("a/__pycache__/b"), false);
    expect(pyCache.matches("a/__pycache"), false);

    final pyCache2 = Glob("**/__pycache__");
    expect(pyCache2.matches("c:/aaa/bbb/__pycache__"), true);
    expect(pyCache2.matches("a/b/__pycache__"), true);

    final binPyCache = Glob("**/bin/__pycache__");
    expect(binPyCache.matches("a/b/bin/__pycache__"), true);

    final numpyTests = Glob("**/numpy/**/tests");
    expect(numpyTests.matches("a/b/numpy/typing/tests"), true);
    expect(numpyTests.matches("a/b/numpy/random/tests"), true);
    expect(numpyTests.matches("a/b/numpy/something/else/tests"), true);
    expect(numpyTests.matches("a/b/package_a/typing/tests"), false);

    final numpyTests2 = Glob("**/numpy/tests");
    expect(numpyTests2.matches("a/b/numpy/tests"), true);
    expect(numpyTests2.matches("a/b/numpy/abc/tests"), false);

    final numpyCoreLib = Glob("**/numpy/_core/lib");
    expect(numpyCoreLib.matches("a/b/numpy/_core/lib"), true);
  });
}
