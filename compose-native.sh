#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# sdk u java 21.3.0.r17-grl
pushd ~/code/compose-mpp-playground >/dev/null
./gradlew packageUberJarForCurrentOS

echo "Generating Graalvm config files..."
java -agentlib:native-image-agent=config-output-dir=config -jar desktop/build/compose/jars/jvm-macos-*.jar

echo "Creating native image ... "
native-image \
      --verbose \
      --no-fallback \
      --allow-incomplete-classpath \
      -H:ConfigurationFileDirectories=config \
      -H:+ReportExceptionStackTraces \
      -Djava.awt.headless=false \
      -J-Xmx7G \
      -jar desktop/build/compose/jars/jvm-macos-*.jar \
      compose-app

# -H:+ReportUnsupportedElementsAtRuntime -H:CLibraryPath=".../lib"
# Resource config options: https://www.graalvm.org/reference-manual/native-image/BuildConfiguration/#:~:text=H%3AResourceConfigurationFiles

echo "Compressing executable ... "
upx compose-app
popd >/dev/null