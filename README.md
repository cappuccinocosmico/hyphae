# Hyphae - Distributed Document Storage System

A self-hosted distributed storage system for managing math textbooks and documents across multiple residential computers. Designed for reliability through replication while maintaining low operational complexity.

## Problem Statement

Scattered math textbooks and documents across various locations need centralized, reliable storage with:
- Multi-location redundancy for data safety
- S3-compatible API for existing backup integrations
- Web-based file management
- Online reading capabilities

## System Requirements

- **Minimum nodes**: 2 (current deployment target)
- **Maximum tolerable downtime**: Moderate (low-stakes environment)
- **Backup strategy**: Manual filesystem-level backups as disaster recovery
- **Network environment**: Residential connections with dynamic IPs
- **Hardware**: Heterogeneous storage sizes across nodes

## Core Features

- **Distributed cluster** across multiple residential computers in different locations
- **S3-compatible API** for integration with existing backup systems
- **Web UI** for file manipulation (hosted on each server)
- **Kavita integration** for online textbook reading via s3fuse filesystem
- **NixOS declarative deployment** using flakes

## Configuration and System Management

All of the computers I want to install this on are already running nix/nixos. And it would be great to find some way to run something like `nix flake apply` to set the configuration on a nixos machine. Have it spin up all the necessary services.

## File Serving

I did a bunch of research into Ceph, SeaweedFS, and Minio, but ultimately think Garage: https://garagehq.deuxfleurs.fr/documentation/quick-start/

is the best since its designed to work well with heterogeneous storage, and is a bit easier to configure, at the cost of performance, which shouldnt matter too much for the files we are storing.

## Networking and Nat Hole Punching

Yggdrasil seems like the most reasonable choice for this. I have used tailscale in the past, but I dont know if going through the hastle of setting up an account with an external service is worth it. And also the technology seems cooler and I have been curious about it for a while.
