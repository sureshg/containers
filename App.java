import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;

public class App {

  public static void main(String[] args) throws IOException {
    var server = HttpServer.create(new InetSocketAddress(80), 0);
    server.createContext("/", new ReqHandler());
    server.setExecutor(null);
    System.out.println("Starting Http Server on port " + server.getAddress().getPort() + "...");
    server.start();
  }

  static class ReqHandler implements HttpHandler {

    public void handle(HttpExchange t) throws IOException {
      var response = """
          Java %s running on %s %s
          """.formatted(
          System.getProperty("java.version"),
          System.getProperty("os.name"),
          System.getProperty("os.arch")
      );
      t.sendResponseHeaders(200, response.length());
      var os = t.getResponseBody();
      os.write(response.getBytes());
      os.close();
    }
  }
}
