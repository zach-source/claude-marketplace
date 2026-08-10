# \!/usr/bin/env python3
"""Utilities for managing Qdrant collections for Claude sessions."""
import os
from typing import List, Optional
from qdrant_client import QdrantClient, models
from qdrant_client.models import Distance, VectorParams, CollectionStatus

# Configuration
QDRANT_HOST = "localhost"
QDRANT_PORT = 6333
VECTOR_SIZE = 768
GLOBAL_COLLECTION = "claude_global"
SESSION_PREFIX = "claude_session_"
LEGACY_COLLECTION = "claude_vectors_encrypted"  # Original collection name


def get_client() -> QdrantClient:
    """Get Qdrant client."""
    return QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, check_compatibility=False)


def collection_exists(client: QdrantClient, name: str) -> bool:
    """Check if a collection exists."""
    try:
        client.get_collection(name)
        return True
    except Exception:
        return False


def create_collection(client: QdrantClient, name: str) -> None:
    """Create a collection if it doesn't exist."""
    if not collection_exists(client, name):
        client.create_collection(
            name,
            vectors_config=VectorParams(size=VECTOR_SIZE, distance=Distance.COSINE),
        )
        print(f"Created collection: {name}")
    else:
        print(f"Collection already exists: {name}")


def get_session_collection_name(session_id: str) -> str:
    """Get collection name for a session."""
    return f"{SESSION_PREFIX}{session_id}"


def ensure_collections(client: QdrantClient, session_id: Optional[str] = None) -> None:
    """Ensure required collections exist."""
    # Always ensure global collection exists
    create_collection(client, GLOBAL_COLLECTION)

    # Create session collection if session_id provided
    if session_id:
        session_collection = get_session_collection_name(session_id)
        create_collection(client, session_collection)


def list_session_collections(client: QdrantClient) -> List[str]:
    """List all session collections."""
    collections = client.get_collections().collections
    session_collections = []

    for collection in collections:
        if collection.name.startswith(SESSION_PREFIX):
            session_collections.append(collection.name)

    return sorted(session_collections)


def get_collection_info(client: QdrantClient, name: str) -> Optional[dict]:
    """Get information about a collection."""
    try:
        info = client.get_collection(name)
        return {
            "name": name,
            "status": info.status,
            "vectors_count": info.vectors_count,
            "points_count": info.points_count,
            "config": {
                "vector_size": info.config.params.vectors.size,
                "distance": info.config.params.vectors.distance,
            },
        }
    except Exception:
        return None


def delete_collection(client: QdrantClient, name: str) -> bool:
    """Delete a collection."""
    try:
        client.delete_collection(name)
        print(f"Deleted collection: {name}")
        return True
    except Exception as e:
        print(f"Failed to delete collection {name}: {e}")
        return False


def migrate_legacy_collection(
    client: QdrantClient, session_id: Optional[str] = None
) -> None:
    """Migrate vectors from legacy collection to new structure."""
    if not collection_exists(client, LEGACY_COLLECTION):
        print(f"Legacy collection {LEGACY_COLLECTION} not found")
        return

    # Ensure target collections exist
    ensure_collections(client, session_id)

    # Get all points from legacy collection
    offset = None
    migrated = 0

    while True:
        result = client.scroll(
            collection_name=LEGACY_COLLECTION,
            offset=offset,
            limit=100,
            with_payload=True,
            with_vectors=True,
        )

        if not result[0]:
            break

        points = result[0]
        offset = result[1]

        # Migrate points to appropriate collection
        for point in points:
            # Determine target collection
            if (
                session_id
                and hasattr(point.payload, "session_id")
                and point.payload.get("session_id") == session_id
            ):
                target_collection = get_session_collection_name(session_id)
            else:
                target_collection = GLOBAL_COLLECTION

            # Copy point to new collection
            client.upsert(collection_name=target_collection, points=[point])
            migrated += 1

    print(f"Migrated {migrated} vectors from legacy collection")


def get_current_session_id() -> Optional[str]:
    """Get current session ID from Claude session file."""
    # Check for .claude-uuid-session in current git root
    current_dir = os.getcwd()

    while current_dir != "/":
        session_file = os.path.join(current_dir, ".claude-uuid-session")
        if os.path.exists(session_file):
            try:
                with open(session_file, "r") as f:
                    return f.read().strip()
            except:
                pass

        # Check if we're at a git root
        if os.path.exists(os.path.join(current_dir, ".git")):
            break

        current_dir = os.path.dirname(current_dir)

    return None


def search_collections(
    client: QdrantClient,
    query_vector: List[float],
    session_id: Optional[str] = None,
    limit: int = 5,
    include_global: bool = True,
    include_session: bool = True,
    include_legacy: bool = True,
) -> List[tuple]:
    """Search across multiple collections."""
    results = []
    collections_to_search = []

    # Determine which collections to search
    if include_global and collection_exists(client, GLOBAL_COLLECTION):
        collections_to_search.append(GLOBAL_COLLECTION)

    if include_session and session_id:
        session_collection = get_session_collection_name(session_id)
        if collection_exists(client, session_collection):
            collections_to_search.append(session_collection)

    if include_legacy and collection_exists(client, LEGACY_COLLECTION):
        collections_to_search.append(LEGACY_COLLECTION)

    # Search each collection
    for collection in collections_to_search:
        try:
            search_result = client.search(
                collection_name=collection, query_vector=query_vector, limit=limit
            )

            # Add collection name to results
            for hit in search_result:
                results.append((collection, hit))
        except Exception as e:
            print(f"Error searching collection {collection}: {e}")

    # Sort by score (descending)
    results.sort(key=lambda x: x[1].score, reverse=True)

    # Return top results
    return results[:limit]


if __name__ == "__main__":
    # Test utilities
    client = get_client()

    print("=== Qdrant Collection Management ===")
    print(f"Connected to Qdrant at {QDRANT_HOST}:{QDRANT_PORT}")

    # List existing collections
    print("\nExisting collections:")
    collections = client.get_collections().collections
    for col in collections:
        info = get_collection_info(client, col.name)
        if info:
            print(f"  - {info['name']}: {info['points_count']} points")

    # Check current session
    session_id = get_current_session_id()
    if session_id:
        print(f"\nCurrent session ID: {session_id}")
    else:
        print("\nNo current session found")

    # List session collections
    session_collections = list_session_collections(client)
    if session_collections:
        print(f"\nFound {len(session_collections)} session collections:")
        for col in session_collections:
            print(f"  - {col}")
