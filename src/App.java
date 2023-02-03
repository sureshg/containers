import com.sun.net.httpserver.HttpServer;

import java.net.InetSocketAddress;
import java.time.Instant;
import java.util.Arrays;
import java.util.Objects;
import java.util.concurrent.Executors;

import static java.lang.System.exit;
import static java.lang.System.out;

public class App {

  public static void main(String[] args) throws Exception {
    var start = System.currentTimeMillis();
    var server = HttpServer.create(new InetSocketAddress(80), 0);
    server.createContext("/", t -> {
      out.println("GET: " + t.getRequestURI());

      var version = "Java %s running on %s %s"
              .formatted(System.getProperty("java.version"),
                      System.getProperty("os.name"),
                      System.getProperty("os.arch"));
      var sb = new StringBuilder(version);
      sb.append(System.lineSeparator()).append(System.lineSeparator());

      sb.append("Command Args:").append(System.lineSeparator());
      sb.append(Arrays.toString(args)).append(System.lineSeparator());
      sb.append(System.lineSeparator()).append(System.lineSeparator());

      sb.append("Env Variables:").append(System.lineSeparator());
      System.getenv().forEach((k, v) -> sb.append(k).append(" : ").append(v).append(System.lineSeparator()));
      sb.append(System.lineSeparator()).append(System.lineSeparator());

      sb.append("System Properties:").append(System.lineSeparator());
      System.getProperties().forEach((k, v) -> sb.append(k).append(" : ").append(v).append(System.lineSeparator()));

      final var res = sb.toString();
      t.sendResponseHeaders(200, res.length());
      try (var os = t.getResponseBody()) {
        os.write(res.getBytes());
      }
    });

    server.createContext("/shutdown", t -> {
      server.stop(0);
      exit(0);
    });
    server.setExecutor(Executors.newCachedThreadPool());
    server.start();

    var isNativeMode = Objects.equals(System.getProperty("org.graalvm.nativeimage.kind", "jvm"), "executable");
    var type = isNativeMode ? "Binary" : "JVM";

    var vmTime = ProcessHandle.current().info().startInstant().orElseGet(Instant::now).toEpochMilli();
    var currTime = System.currentTimeMillis();

    out.println("Starting Http Server on port " + server.getAddress().getPort() + "...");
    out.printf("Started in %d millis! (%s: %dms, App: %dms)%n",
            (currTime - vmTime),
            type,
            (start - vmTime),
            (currTime - start)
    );
  }
}
