import com.beust.jcommander.JCommander;

import java.sql.SQLException;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.IntStream;

public class Benchmark {

    private static final AtomicBoolean started = new AtomicBoolean(false);
    private static final AtomicBoolean stopped = new AtomicBoolean(false);
    private static final AtomicInteger totalTransactions = new AtomicInteger(0);
    private static final AtomicInteger abortedTransactions = new AtomicInteger(0);
    private static final AtomicLong totalRt = new AtomicLong(0);
    private static final ConcurrentHashMap<TransactionType, AtomicLong[]> rtPerType = new ConcurrentHashMap<>();


    public static void execute(Options options) throws Exception {
        System.out.println("Setting up");
        List<Worker> workers = IntStream.range(0, options.clients)
                .parallel()
                .mapToObj(i -> {
                    try {
                        return new Worker(
                                started, stopped, totalTransactions, abortedTransactions, totalRt, rtPerType, options
                        );
                    } catch (SQLException e) {
                        throw new RuntimeException(e);
                    }
                })
                .toList();

        for (Worker w : workers) {
            w.start();
        }

        System.out.println("Warmup");
        Thread.sleep(options.warmup * 1000L);

        System.out.println("Started");
        started.set(true);
        long start = System.nanoTime();
        Thread.sleep(options.runtime * 1000L);
        double runtime = (System.nanoTime() - start) / 1e9;
        started.set(false);
        stopped.set(true);

        for (Worker w : workers) {
            w.join();
        }

        printResults(runtime);
    }


    public static void printResults(double runtime) {
        DecimalFormatSymbols symbols = new DecimalFormatSymbols(Locale.US);
        DecimalFormat df = new DecimalFormat("0.000", symbols);
        System.out.println("Response time per function (ms)");
        System.out.println("-------------------------------");
        rtPerType.entrySet()
                .stream()
                .sorted(Map.Entry.comparingByKey())
                .forEach(e -> System.out.println(
                        e.getKey() + " = " + df.format(e.getValue()[0].get() / (e.getValue()[1].get() * 1e6d))
                ));

        System.out.println("\nOverall metrics");
        System.out.println("---------------");
        System.out.println("throughput (txn/s) = " + df.format(totalTransactions.get() / runtime));
        System.out.println("response time (ms) = " + df.format(totalRt.get() / (totalTransactions.get() * 1e6d)));
        System.out.println("abort rate (%) = " + df.format(abortedTransactions.get() * 100 / ((double) totalTransactions.get())));
    }


    public static void main(String[] args) throws Exception {
        Options options = new Options();
        JCommander parser = JCommander.newBuilder()
                .addObject(options)
                .build();
        try {
            parser.parse(args);
            if (options.help) {
                parser.usage();
                return;
            }
        } catch (Exception e) {
            parser.usage();
            return;
        }

        execute(options);
    }
}
