package model;

public record Repository(
    int id,
    String name,
    String owner,
    String description
) {
}
