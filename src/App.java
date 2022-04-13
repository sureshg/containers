import static java.lang.System.out;

import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;

public class App {

  public static void main(String[] args) throws Exception {

    var start = System.currentTimeMillis();
    var server = HttpServer.create(new InetSocketAddress(80), 0);
    server.createContext("/", t -> {
      out.println("GET: " + t.getRequestURI());
      var res = "Java %s running on %s %s".formatted(
          System.getProperty("java.version"),
          System.getProperty("os.name"),
          System.getProperty("os.arch")
      );
      t.sendResponseHeaders(200, res.length());
      try (var os = t.getResponseBody()) {
        os.write(res.getBytes());
      }
    });

    server.createContext("/shutdown", t -> System.exit(0));
    server.start();
    out.println("Starting Http Server on port " + server.getAddress().getPort() + ". Took "
        + (System.currentTimeMillis() - start) + " millis!");
  }
}
