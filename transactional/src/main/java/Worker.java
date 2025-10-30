import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

public class Worker extends Thread {

    private final AtomicBoolean started, stopped;
    private final AtomicInteger totalTransactions, abortedTransactions;
    private final AtomicLong totalRt;
    private final ConcurrentHashMap<TransactionType, AtomicLong[]> rtPerType;
    private final Connection conn;
    private final Workload workload;


    public Worker(AtomicBoolean started, AtomicBoolean stopped, AtomicInteger totalTransactions,
                  AtomicInteger abortedTransactions, AtomicLong totalRt,
                  ConcurrentHashMap<TransactionType, AtomicLong[]> rtPerType, Options options) throws SQLException {
        this.started = started;
        this.stopped = stopped;
        this.totalTransactions = totalTransactions;
        this.abortedTransactions = abortedTransactions;
        this.totalRt = totalRt;
        this.rtPerType = rtPerType;
        this.conn = DriverManager.getConnection(options.database, options.user, options.passwd);
        this.workload = new Workload(this.conn);
    }


    public void run() {
        try {
            while (!stopped.get()) {
                long before = System.nanoTime();
                boolean success = true;
                TransactionType type = null;
                try {
                    type = workload.transaction();
                } catch (SQLException e) {
                    // check if it is an isolation or uniqueness-related exception
                    // make sure other exceptions are shown
                    if (e.getSQLState().startsWith("40") || e.getSQLState().startsWith("23")) {
                        try {
                            conn.rollback();
                        } catch (Exception ignored) {}
                        success = false;
                    } else {
                        throw e;
                    }
                } finally {
                    long after = System.nanoTime();
                    logTransaction(after - before, success, type);
                }
            }
            conn.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }


    public void logTransaction(long rt, boolean success, TransactionType type) {
        if (started.get() && !stopped.get()) {
            totalTransactions.incrementAndGet();
            totalRt.addAndGet(rt);
            if (!success) {
                abortedTransactions.incrementAndGet();
            } else {
                rtPerType.putIfAbsent(type, new AtomicLong[]{new AtomicLong(0), new AtomicLong(0)});
                rtPerType.get(type)[0].addAndGet(rt);
                rtPerType.get(type)[1].incrementAndGet();
            }
        }
    }
}
