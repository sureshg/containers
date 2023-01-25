import static java.lang.System.exit;
import static java.lang.System.out;

import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.time.Instant;
import java.util.Objects;

public class App {

  public static void main(String[] args) throws Exception {
    var start = System.currentTimeMillis();
    var server = HttpServer.create(new InetSocketAddress(80), 0);
    server.createContext("/", t -> {
      out.println("GET: " + t.getRequestURI());
      var res = "Java %s running on %s %s".formatted(System.getProperty("java.version"),
          System.getProperty("os.name"), System.getProperty("os.arch"));
      t.sendResponseHeaders(200, res.length());
      try (var os = t.getResponseBody()) {
        os.write(res.getBytes());
      }
    });

    server.createContext("/shutdown", t -> {
      server.stop(0);
      exit(0);
    });
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
