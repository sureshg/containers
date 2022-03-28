import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;

public class App {

  public static void main(String[] args) throws Exception {
    var server = HttpServer.create(new InetSocketAddress(80), 0);
    server.setExecutor(null);
    server.createContext("/", t -> {
      // System.out.println("GET " + t.getRequestURI());
      var resp = "Java %s running on %s %s".formatted(
          System.getProperty("java.version"),
          System.getProperty("os.name"),
          System.getProperty("os.arch")
      );
      t.sendResponseHeaders(200, resp.length());
      var os = t.getResponseBody();
      os.write(resp.getBytes());
      os.close();
    });

    System.out.println("Starting Http Server on port " + server.getAddress().getPort() + "...");
    server.start();
  }
}
