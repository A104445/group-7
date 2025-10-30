import static java.util.Map.entry;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Random;

import model.Repository;
import model.RepositoryPage;
import model.Ticket;
import model.TicketId;
import model.User;

public class Workload {

    private final Random rand = new Random();
    private final Connection conn;
    private PreparedStatement addRepository, addStar, addCommit, updateRepositoryCommit, addTicket,
            closeTicket, getRepositoryPage, getRepositoriesByLanguage, getUser, getUserRepositories,
            getTicketPage, searchRepositoryByDescription;

    // Counters and lists to select random identifiers
    private int numRepositories;
    private int numLanguages;
    private List<String> usernamesSample = new ArrayList<>();
    private List<TicketId> openTicketsSample = new ArrayList<>();

    // Note: while this list is static, we should be able to provide any search token.
    private final List<String> searchTokens = List.of("api & rest", "arduino", "automated", "benchmark", "c++", "cloud",
            "controller", "database", "docker", "game", "go", "html | css | js", "java", "linux", "machine & learning",
            "memory", "nodejs", "python", "react & !native", "react & native", "rust", "spring", "sql",
            "web & framework", "windows");

    // weights for each transaction type
    private final List<Map.Entry<TransactionType, Integer>> transactionWeights = List.of(
            entry(TransactionType.CreateRepository, 1),
            entry(TransactionType.StarRepository, 5),
            entry(TransactionType.CreateCommit, 20),
            entry(TransactionType.CreateTicket, 15),
            entry(TransactionType.CloseTicket, 4),
            entry(TransactionType.GetRepositoryInfo, 20),
            entry(TransactionType.GetRepositoriesByLanguage, 5),
            entry(TransactionType.GetUserInfo, 5),
            entry(TransactionType.GetTicketInfo, 20),
            entry(TransactionType.SearchRepositories, 5)
    );
    private final int totalWeight = transactionWeights.stream().mapToInt(Map.Entry::getValue).sum();


    public Workload(Connection c) throws SQLException {
        conn = c;
        conn.setAutoCommit(false); // autocommit = off to execute operations inside a transaction
        prepareStatements();
        populateIds();
    }


    /**
     * Prepares the statements used in this workload
     */
    private void prepareStatements() throws SQLException {
        addRepository = conn.prepareStatement("""
            insert into repository (id, name, owner, is_archived, disk_usage_kb, description, created_at, pushed_at, code_of_conduct)
            values (default, ?, ?, false, 0, ?, now(), now(), null)
        """);

        addStar = conn.prepareStatement("""
            insert into star (repository_id, username, starred_at)
            values (?, ?, now())
        """);

        addCommit = conn.prepareStatement("""
            insert into commit (repository_id, hash, created_by, message, created_at)
            values (?, ?, ?, ?, now())
        """);

        updateRepositoryCommit = conn.prepareStatement("""
            update repository
            set disk_usage_kb = disk_usage_kb + ?,
                pushed_at = now()
            where id = ?
        """);

        addTicket = conn.prepareStatement("""
            insert into ticket (repository_id, ticket_id, created_by, type, status, opened_at, closed_at, title, data)
            select ?,
                (select coalesce(max(ticket_id) + 1, 1) from ticket where repository_id = ?),
                ?, ?, 'open', now(), null, ?, ?
        """);

        closeTicket = conn.prepareStatement("""
            update ticket
            set status = (case when type = 'pull_request' then 'merged' else 'closed' end)
            where repository_id = ? and ticket_id = ?
        """);

        getRepositoryPage = conn.prepareStatement("""
            select name,
                owner,
                is_archived,
                description,
                (
                    select l.name
                    from repository_license rl
                    join license l on l.id = rl.license_id
                    where rl.repository_id = r.id
                ) as license,
                (
                    select coalesce(array_agg(l.name || ': ' || rl.size), '{}')
                    from repository_languages rl
                    join language l on l.id = rl.language_id
                    where rl.repository_id = r.id
                ) as languages,
                (
                    select coalesce(array_agg(t.name), '{}')
                    from repository_topics rt
                    join topic t on t.id = rt.topic_id
                    where rt.repository_id = r.id
                ) as topics,
                (
                    select count(*)
                    from commit
                    where repository_id = r.id
                ) as commits,
                (
                    select count(*)
                    from star
                    where repository_id = r.id
                ) as stars,
                (
                    select hash || ' by ' || created_by || ' at ' || created_at || ': ' || message
                    from commit
                    where repository_id = r.id
                    order by created_at desc
                    limit 1
                ) as latest_commit
            from repository r
            where id = ?
        """);

        getRepositoriesByLanguage = conn.prepareStatement("""
            select r.id, r.name, r.owner, r.description
            from repository r
            join repository_languages rl on rl.repository_id = r.id
            join language l on l.id = rl.language_id
            where l.id = ?
            order by r.created_at desc
            limit 100
        """);

        getUser = conn.prepareStatement("""
            select created_at, bio
            from users
            where username = ?
        """);

        getUserRepositories = conn.prepareStatement("""
            select r.id, r.name, r.description
            from repository r
            join users u on u.username = r.owner
            where u.username = ?
            order by pushed_at desc
            limit 10
        """);

        getTicketPage = conn.prepareStatement("""
            select created_by, type, status, opened_at, closed_at, title, data
            from ticket
            where repository_id = ?
                and ticket_id = ?
        """);

        searchRepositoryByDescription = conn.prepareStatement("""
            select id, name, owner, description
            from repository
            where to_tsvector('english', description) @@ to_tsquery('english', ?)
            limit 100
        """);
    }


    /**
     * Populates each entity with random identifiers
     */
    private void populateIds() throws SQLException {
        Statement s = this.conn.createStatement();

        ResultSet rs = s.executeQuery("select count(*) from repository");
        rs.next();
        numRepositories = rs.getInt(1);

        rs = s.executeQuery("select count(*) from language");
        rs.next();
        numLanguages = rs.getInt(1);

        rs = s.executeQuery("select username from users order by random() limit 100000");
        while (rs.next()) {
            usernamesSample.add(rs.getString(1));
        }

        rs = s.executeQuery(
                "select repository_id, ticket_id from ticket where status = 'open' order by random() limit 25000");
        while (rs.next()) {
            openTicketsSample.add(new TicketId(rs.getInt(1), rs.getInt(2)));
        }
    }


    /**
     * Creates a new repository.
     */
    private void createRepository() throws SQLException {
        String name = Utils.randomString(10);
        String username = Utils.randomElement(usernamesSample);
        String description = Utils.randomString(50);

        Utils.setPreparedStatementArgs(addRepository, name, username, description);
        addRepository.executeUpdate();
        conn.commit();
    }


    /**
     * Adds a star to a repository.
     */
    private void starRepository() throws SQLException {
        int repositoryId = rand.nextInt(numRepositories) + 1;
        String username = Utils.randomElement(usernamesSample);

        Utils.setPreparedStatementArgs(addStar, repositoryId, username);
        addStar.executeUpdate();
        conn.commit();
    }


    /**
     * Creates a new commit.
     */
    private void createCommit() throws Exception {
        int repositoryId = rand.nextInt(numRepositories) + 1;
        String hash = Utils.randomHash();
        String username = Utils.randomElement(usernamesSample);
        String message = Utils.randomString(50);
        int diskUsageDelta = rand.nextInt(-10, 10);

        Utils.setPreparedStatementArgs(addCommit, repositoryId, hash, username, message);
        addCommit.executeUpdate();
        Utils.setPreparedStatementArgs(updateRepositoryCommit, diskUsageDelta, repositoryId);
        updateRepositoryCommit.executeUpdate();
        conn.commit();
    }


    /**
     * Creates a new ticket.
     */
    private void createTicket() throws SQLException {
        int repositoryId = rand.nextInt(numRepositories) + 1;
        String username = Utils.randomElement(usernamesSample);
        String type = rand.nextFloat() < 0.7 ? "issue" : "pull_request";
        String title = Utils.randomString(50);
        String data = Utils.randomString(500);

        Utils.setPreparedStatementArgs(addTicket, repositoryId, repositoryId, username, type, title, data);
        addTicket.executeUpdate();
        conn.commit();
    }


    /**
     * Closes an existing ticket (closes an issue or merges a pull request).
     */
    private void closeTicket() throws SQLException {
        TicketId id = openTicketsSample.removeLast();

        Utils.setPreparedStatementArgs(closeTicket, id.repositoryId(), id.ticketId());
        closeTicket.executeUpdate();
        conn.commit();
    }


    /**
     * Retrieves the complete information about a repository.
     */
    private RepositoryPage getRepositoryInfo() throws SQLException {
        int repositoryId = rand.nextInt(numRepositories) + 1;

        Utils.setPreparedStatementArgs(getRepositoryPage, repositoryId);
        ResultSet rs = getRepositoryPage.executeQuery();
        rs.next();

        String name = rs.getString(1);
        String owner = rs.getString(2);
        boolean isArchived = rs.getBoolean(3);
        String description = rs.getString(4);
        String license = rs.getString(5);
        List<String> languages = Arrays.stream((String[]) rs.getArray(6).getArray()).toList();
        List<String> topics = Arrays.stream((String[]) rs.getArray(7).getArray()).toList();
        int commits = rs.getInt(8);
        int stars = rs.getInt(9);
        String latestCommit = rs.getString(10);

        RepositoryPage page = new RepositoryPage(
            repositoryId, name, owner, isArchived, description, license, languages, topics, commits, stars, latestCommit
        );

        conn.commit();
        return page;
    }


    /**
     * Retrieves the most recent repository for a given programming language.
     */
    private List<Repository> getRepositoriesByLanguage() throws SQLException {
        int languageId = rand.nextInt(numLanguages) + 1;

        Utils.setPreparedStatementArgs(getRepositoriesByLanguage, languageId);
        ResultSet rs = getRepositoriesByLanguage.executeQuery();

        List<Repository> repositories = new ArrayList<>();
        while (rs.next()) {
            int repositoryId = rs.getInt(1);
            String name = rs.getString(2);
            String owner = rs.getString(3);
            String description = rs.getString(4);
            Repository repository = new Repository(repositoryId, name, owner, description);
            repositories.add(repository);
        }

        conn.commit();
        return repositories;
    }


    /**
     * Retrieves a user's profile.
     */
    private User getUserInfo() throws SQLException {
        String username = Utils.randomElement(usernamesSample);

        Utils.setPreparedStatementArgs(getUser, username);
        Utils.setPreparedStatementArgs(getUserRepositories, username);

        ResultSet rs = getUser.executeQuery();
        rs.next();
        LocalDateTime createdAt = rs.getTimestamp(1).toLocalDateTime();
        String bio = rs.getString(2);

        rs = getUserRepositories.executeQuery();
        List<Repository> repositories = new ArrayList<>();
        while (rs.next()) {
            int repositoryId = rs.getInt(1);
            String name = rs.getString(2);
            String description = rs.getString(3);
            Repository repository = new Repository(repositoryId, name, username, description);
            repositories.add(repository);
        }

        User user = new User(username, createdAt, bio, repositories);

        conn.commit();
        return user;
    }


    /**
     * Retrieves the information of a ticket.
     */
    private Ticket getTicketInfo() throws SQLException {
        TicketId id = Utils.randomElement(openTicketsSample);

        Utils.setPreparedStatementArgs(getTicketPage, id.repositoryId(), id.ticketId());
        ResultSet rs = getTicketPage.executeQuery();
        rs.next();

        String createdBy = rs.getString(1);
        String type = rs.getString(2);
        String status = rs.getString(3);
        LocalDateTime openedAt = rs.getTimestamp(4).toLocalDateTime();
        LocalDateTime closedAt = rs.getTimestamp(5) != null ? rs.getTimestamp(5).toLocalDateTime() : null;
        String title = rs.getString(6);
        String data = rs.getString(7);

        Ticket ticket = new Ticket(
            id.repositoryId(), id.ticketId(), createdBy, type, status, openedAt, closedAt, title, data
        );

        conn.commit();
        return ticket;
    }


    /**
     * Retrieves a subset of repositories whose description matches some search query.
     */
    private List<Repository> searchRepositories() throws SQLException {
        String query = Utils.randomElement(searchTokens);

        Utils.setPreparedStatementArgs(searchRepositoryByDescription, query);
        ResultSet rs = searchRepositoryByDescription.executeQuery();

        List<Repository> repositories = new ArrayList<>();
        while (rs.next()) {
            int id = rs.getInt(1);
            String name = rs.getString(2);
            String owner = rs.getString(3);
            String description = rs.getString(4);
            Repository repository = new Repository(id, name, owner, description);
            repositories.add(repository);
        }

        conn.commit();
        return repositories;
    }


    /**
     * Randomly selects a TransactionType, based on the weights in this.transactionWeights
     */
    private TransactionType getRandomTransaction() throws NullPointerException {
        int r = rand.nextInt(0, totalWeight);
        int curr = 0;

        for (var entry : transactionWeights) {
            if (r < entry.getValue() + curr) {
                return entry.getKey();
            }
            curr += entry.getValue();
        }

        throw new NullPointerException();
    }


    /**
     * Executes a random transaction
     */
    public TransactionType transaction() throws Exception {
        var type = getRandomTransaction();

        switch (type) {
            case CreateRepository -> createRepository();
            case StarRepository -> starRepository();
            case CreateCommit -> createCommit();
            case CreateTicket -> createTicket();
            case CloseTicket -> closeTicket();
            case GetRepositoryInfo -> getRepositoryInfo();
            case GetRepositoriesByLanguage -> getRepositoriesByLanguage();
            case GetUserInfo -> getUserInfo();
            case GetTicketInfo -> getTicketInfo();
            case SearchRepositories -> searchRepositories();
        }

        return type;
    }
}
