import com.sun.net.httpserver.HttpServer;

import java.net.InetSocketAddress;
import java.time.Instant;
import java.util.Arrays;
import java.util.Objects;
import java.util.concurrent.Executors;
import java.util.stream.Collectors;

import static java.lang.System.exit;
import static java.lang.System.out;

void main(String[] args) throws Exception {
    var start = System.currentTimeMillis();
    var server = HttpServer.create(new InetSocketAddress(80), 0);
    server.createContext(
            "/",
            t -> {
                out.printf("GET: %s%n", t.getRequestURI());
                long unit = 1024 * 1024L;
                long heapSize = Runtime.getRuntime().totalMemory();
                long heapFreeSize = Runtime.getRuntime().freeMemory();
                long heapUsedSize = heapSize - heapFreeSize;
                long heapMaxSize = Runtime.getRuntime().maxMemory();
                var nl = System.lineSeparator();

                var sysProps = System.getProperties().entrySet()
                        .stream()
                        .map(e -> "%s : %s".formatted(e.getKey(), e.getValue()))
                        .collect(Collectors.joining(nl));

                var envVars = System.getenv().entrySet()
                        .stream()
                        .map(e -> "%s : %s".formatted(e.getKey(), e.getValue()))
                        .collect(Collectors.joining(nl));

                final var res = """
                                       • [JVM] Java %s
                                       • [OS] %s %s
                                       • [Args] Command Args: %s
                                       • [CPU] Active Processors: %d
                                       • [Mem] Current Heap Size (Committed): %d MiB
                                       • [Mem] Current Free memory in Heap: %d MiB
                                       • [Mem] Currently used memory: %d MiB
                                       • [Mem] Max Heap Size (-Xmx): %d MiB
                                       • [Thread] %s
                                       • [Env] Variables:
                                       %s
                                       • [System] Properties:
                                       %s
                                       """.formatted(
                        System.getProperty("java.version"),
                        System.getProperty("os.name"),
                        System.getProperty("os.arch"),
                        Arrays.toString(args),
                        Runtime.getRuntime().availableProcessors(),
                        heapSize / unit,
                        heapFreeSize / unit,
                        heapUsedSize / unit,
                        heapMaxSize / unit,
                        Thread.currentThread(),
                        envVars,
                        sysProps
                ).getBytes();

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

    var isNativeMode = Objects.equals(System.getProperty("org.graalvm.nativeimage.kind", "jvm"), "executable");
    var type = isNativeMode ? "Binary" : "JVM";

    var vmTime = ProcessHandle.current().info().startInstant().orElseGet(Instant::now).toEpochMilli();
    var currTime = System.currentTimeMillis();

    out.printf("Starting Http Server on port %d%n", server.getAddress().getPort());
    out.printf("Started in %d millis! (%s: %dms, App: %dms)%n",
            currTime - vmTime,
            type,
            start - vmTime,
            currTime - start
    );
}
