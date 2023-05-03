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

      var nl = System.lineSeparator();
      var version = "• [JVM] Java %s running on %s %s".formatted(System.getProperty("java.version"), System.getProperty("os.name"), System.getProperty("os.arch"));
      var sb = new StringBuilder(version);
      sb.append(nl);

      sb.append("• [Args] Command Args: ").append(Arrays.toString(args)).append(nl);

      long unit = 1024 * 1024L;
      long heapSize = Runtime.getRuntime().totalMemory();
      long heapFreeSize = Runtime.getRuntime().freeMemory();
      long heapUsedSize = heapSize-heapFreeSize;
      long heapMaxSize = Runtime.getRuntime().maxMemory();

      sb.append("• [CPU] Active Processors             : ").append(Runtime.getRuntime().availableProcessors()).append(nl)
        .append("• [Mem] Current Heap Size (Committed) : ").append(heapSize / unit).append(" MiB").append(nl)
        .append("• [Mem] Current Free memory in Heap   : ").append(heapFreeSize / unit).append(" MiB").append(nl)
        .append("• [Mem] Currently used memory         : ").append(heapUsedSize / unit).append(" MiB").append(nl)
        .append("• [Mem] Max Heap Size (-Xmx)          : ").append(heapMaxSize / unit).append(" MiB").append(nl)
        .append("• [Thread] Virtual                    : ").append(Thread.currentThread()).append(nl).append(nl);

      sb.append("• [Env] Variables:").append(nl);
      System.getenv().forEach((k, v) -> sb.append(k).append(" : ").append(v).append(nl));
      sb.append(nl).append(nl);

      sb.append("• [System] Properties:").append(nl);
      System.getProperties().forEach((k, v) -> sb.append(k).append(" : ").append(v).append(nl));

      final var res = sb.toString().getBytes();
      t.sendResponseHeaders(200, res.length);
      try (var os = t.getResponseBody()) {
        os.write(res);
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
