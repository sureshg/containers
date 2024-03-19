import com.sun.net.httpserver.HttpServer;

import java.net.InetSocketAddress;
import java.time.Instant;
import java.util.Arrays;
import java.util.Objects;
import java.util.concurrent.Executors;
import java.util.stream.Collectors;

import static java.lang.System.exit;
import static java.lang.System.out;
import static java.util.FormatProcessor.FMT;

void main(String[] args) throws Exception {
    var start = System.currentTimeMillis();
    var server = HttpServer.create(new InetSocketAddress(80), 0);
    server.createContext(
            "/",
            t -> {
                out.println(STR."GET: \{t.getRequestURI()}");
                long unit = 1024 * 1024L;
                long heapSize = Runtime.getRuntime().totalMemory();
                long heapFreeSize = Runtime.getRuntime().freeMemory();
                long heapUsedSize = heapSize - heapFreeSize;
                long heapMaxSize = Runtime.getRuntime().maxMemory();
                var nl = System.lineSeparator();

                final var res = STR."""
                • [JVM] Java \{System.getProperty("java.version")}
                • [OS] \{System.getProperty("os.name")} \{System.getProperty("os.arch")}
                • [Args] Command Args: \{Arrays.toString(args)}
                • [CPU] Active Processors: \{Runtime.getRuntime().availableProcessors()}
                • [Mem] Current Heap Size (Committed): \{heapSize / unit} MiB
                • [Mem] Current Free memory in Heap: \{heapFreeSize / unit} MiB
                • [Mem] Currently used memory: \{heapUsedSize / unit} MiB
                • [Mem] Max Heap Size (-Xmx): \{heapMaxSize / unit} MiB
                • [Thread] \{Thread.currentThread()}

                • [Env] Variables:
                \{System.getenv().entrySet()
                          .stream()
                          .map(e -> STR."\{e.getKey()} : \{e.getValue()}")
                          .collect(Collectors.joining(nl)) }

                • [System] Properties:
                \{System.getProperties().entrySet()
                          .stream()
                          .map(e -> STR."\{e.getKey()} : \{e.getValue()}")
                          .collect(Collectors.joining(nl))}
                """.getBytes();

                t.sendResponseHeaders(200, res.length);
                try (var os = t.getResponseBody()) {
                    os.write(res);
                }
            });

    server.createContext(
            "/shutdown",
            t -> {
                server.stop(0);
                exit(0);
            });

    server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
    server.start();

    var isNativeMode =
            Objects.equals(System.getProperty("org.graalvm.nativeimage.kind", "jvm"), "executable");
    var type = isNativeMode ? "Binary" : "JVM";

    var vmTime =
            ProcessHandle.current().info().startInstant().orElseGet(Instant::now).toEpochMilli();
    var currTime = System.currentTimeMillis();

    out.println(STR."Starting Http Server on port \{server.getAddress().getPort()}...");
    out.println(FMT."Started in %d\{currTime - vmTime} millis! (%s\{type}: %d\{start - vmTime}ms, App: %d\{currTime - start}ms)");
}
