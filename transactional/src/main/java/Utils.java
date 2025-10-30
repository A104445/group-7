import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.sql.*;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.Random;
import java.util.stream.IntStream;

public class Utils {

    private static final Random random = new Random();
    private static final Random secureRandom = new SecureRandom();
    private static final char[] chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".toCharArray();


    public static String randomString(int n) {
        return IntStream.range(0, n)
                .mapToObj(x -> chars[random.nextInt(chars.length)])
                .map(Object::toString)
                .reduce((acc, x) -> acc + x)
                .get();
    }


    public static String randomHash() throws NoSuchAlgorithmException {
        byte[] bytes = new byte[16];
        random.nextBytes(bytes);
        var hash = MessageDigest.getInstance("SHA-1").digest(bytes);
        return HexFormat.of().formatHex(hash);
    }


    @SafeVarargs
    public static <T> T randomElement(List<T> ...lists) {
        var list = lists[random.nextInt(lists.length)];
        return list.get(random.nextInt(list.size()));
    }
    
    
    public static void setPreparedStatementArgs(PreparedStatement statement, Object... args) throws SQLException {
        int index = 1;
        for (Object arg : args) {
            switch (arg) {
                case Integer i -> statement.setInt(index, i);
                case Long l -> statement.setLong(index, l);
                case Double d -> statement.setDouble(index, d);
                case String s -> statement.setString(index, s);
                case Boolean b -> statement.setBoolean(index, b);
                case LocalDate l -> statement.setDate(index, Date.valueOf(l));
                case LocalDateTime l -> statement.setTimestamp(index, Timestamp.valueOf(l));
                case List l -> {
                    Connection conn = statement.getConnection();
                    statement.setArray(index, conn.createArrayOf("varchar", l.toArray()));
                }
                default -> {
                    assert(false);
                }
            }
            index++;
        }
    }
}
