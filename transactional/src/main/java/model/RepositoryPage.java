package model;

import java.util.List;

public record RepositoryPage(
    int id,
    String name,
    String owner,
    boolean isArchived,
    String description,
    String license,
    List<String> languages,
    List<String> topics,
    int commits,
    int stars,
    String latestCommit
) {
}
