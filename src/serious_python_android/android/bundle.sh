if [ -z "$SERIOUS_PYTHON_P4A_DIST" ] || [ ! -d "$SERIOUS_PYTHON_P4A_DIST" ]
then
  echo "Environment variable 'SERIOUS_PYTHON_P4A_DIST' is not set or does not point to a valid directory."
  exit 1
fi

echo "Copying P4A libraries from $SERIOUS_PYTHON_P4A_DIST"

JNI_LIBS_DIR=src/main/jniLibs
BUNDLE_NAME=libpythonbundle.so

# clean up
rm -rf $JNI_LIBS_DIR
mkdir -p $JNI_LIBS_DIR

echo "Bundling arm64-v8a"
cd $SERIOUS_PYTHON_P4A_DIST/_python_bundle__arm64-v8a/_python_bundle
zip -r $BUNDLE_NAME . > /dev/null
mv $BUNDLE_NAME ../../libs/arm64-v8a
cd -

echo "Bundling armeabi-v7a"
cd $SERIOUS_PYTHON_P4A_DIST/_python_bundle__armeabi-v7a/_python_bundle
zip -r $BUNDLE_NAME . > /dev/null
mv $BUNDLE_NAME ../../libs/armeabi-v7a
cd -

echo "Bundling armeabi-v7a"
cd $SERIOUS_PYTHON_P4A_DIST/_python_bundle__x86_64/_python_bundle
zip -r $BUNDLE_NAME . > /dev/null
mv $BUNDLE_NAME ../../libs/x86_64
cd -

echo "Copying all .so files to `realpath $JNI_LIBS_DIR`"
cp -R $SERIOUS_PYTHON_P4A_DIST/libs/* $JNI_LIBS_DIR