# Backend Engineering Take-Home Assignment: Dynamic Pricing Proxy

# Design Overview
Implement Rails Cache with Redis backend in `PricingService` to reduce the number of calls to the external API.

## System Requirements
1. Ensure rates are never older than 5 minutes - implement caching with 5 minute TTL
2. Protect the external API (limited to 1,000 requests per day)
3. Our service should be able to handle at least 10,000 requests per day from our user

Knowing these requirements, we know that we would not be able to directly call the external API for every request, as that would quickly exhaust our daily limit. We need to implement a strategy to reduce the number of calls to the external API.

## Options
1. No Caching - Will violate the throughput constraint in no time, Waste API Token
2. Prefetching data in the Background - Adds complexity, will need to prefetch data for every 5 minutes
3. In-Memory Caching - Simple but not distributed, will not work if we have multiple instances
4. Cache Implementation - Use Rails Cache with Redis backend for distributed caching so that all instances share the same cache ✅

## High Level Flow:
<img width="1131" height="679" alt="ArchDiagram" src="https://github.com/user-attachments/assets/a1feaff9-e25e-4ecf-b4be-9be26d4e9488" />

1. Generate cache keys based on the request parameters
`pricing_rate:<period>:<hotel>:<room>`
2. Our service checks if the rate is in cache
   - If the rate is in cache, return the cached rate
   - If the rate is not in cache, call the external API and cache the result with a 5 minute TTL
3. Return the rate to the client

## Technical Decisions:
**Rails Cache with Redis backend for distributed caching**
* Distributed across multiple instances and persistence across container restarts, meaning if we have 5 instances of our service running, they will all share the same cache
* TTL of 5 minutes to ensure rates are never older than 5 minutes
* At first, I want to use Kredis (https://github.com/rails/kredis), but I realize about the possibility of race conditions, where let say 10 requests come in at the same time and all of them miss the cache, then all 10 requests will call the external API and cache the result. This might lead to unnecessary load on the external API, so I decided to use Rails Cache where they have built-in support for distributed locking using race_condition_ttl to prevent race conditions (https://api.rubyonrails.org/v8.1/classes/ActiveSupport/Cache/Store.html)
* The trade off using this TTL would be, a slightly stale value (in our case, I set it into 10 seconds) may be served. But this is intentional to preserve system stability and protect external API.
* skip_nil to prevents caching failed or nil responses, to avoid serving invalid data for 5 minutes

**Cache Key = `pricing_rate:<period>:<hotel>:<room>`**
* The rate is specific to the period, hotel, and room
* It's easy to debug and monitor specific cache entries
* It's easy to invalidate specific cache entries

**Error Handling**
- External API failure will be translated into domain-level error (such as Rate not found or Rate unavailable) to prevent raw external API errors shown to the user

## AI Usage
- Use Windsurf for generate the unit test code after prompting the cases that need to be tested
- Use ChatGPT base model for debugging and general assistance

## How to Run
```bash

# --- 1. Build & Run The Main Application ---
# Build and run the Docker compose
docker compose up -d --build

# --- 2. Test The Endpoint ---
# Send a sample request to your running service
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'

# --- 3. Run Tests ---
# Run the full test suite
docker compose exec interview-dev ./bin/rails test

# Run a test file for pricing service
docker compose exec interview-dev ./bin/rails test test/services/api/v1/pricing_service_test.rb

# Run Rails Console for Debugging
docker compose exec interview-dev ./bin/rails console
```

---

Welcome to the Tripla backend engineering take-home assignment\! 🧑‍💻 This exercise is designed to simulate a real-world problem you might encounter as part of our team.

⚠️ **Before you begin**, please review the main [FAQ](/README.md#frequently-asked-questions). It contains important information, **including our specific guidelines on how to submit your solution.**

## The Challenge

At Tripla, we use a dynamic pricing model for hotel rooms. Instead of static, unchanging rates, our model uses a real-time algorithm to adjust prices based on market demand and other data signals. This helps us maximize both revenue and occupancy.

Our Data and AI team built a powerful model to handle this, but its inference process is computationally expensive to run. To make this product more cost-effective, we analyzed the model's output and found that a calculated room rate remains effective for up to 5 minutes.

This insight presents a great optimization opportunity, and that's where you come in.

## Your Mission

Your mission is to build an efficient service that acts as an intermediary to our dynamic pricing model. This service will be responsible for providing rates to our users while respecting the operational constraints of the expensive model behind it.

You will start with a Ruby on Rails application that is already integrated with our dynamic pricing model. However, the current implementation fetches a new rate for every single request. Your mission is to ensure this service handles the pricing models' constraints.

## Core Requirements

1. Review the pricing model's API and its constraints. The model's docker image and documentation are hosted on dockerhub:  [tripladev/rate-api](https://hub.docker.com/r/tripladev/rate-api).

2. Ensure rate validity. A rate fetched from the pricing model is considered valid for 5 minutes. Your service must ensure that any rate it provides for a given set of parameters (`period`, `hotel`, `room`) is no older than this 5-minute window.

3. Honor throughput requirements. Your solution must be able to handle at least 10,000 requests per day from our users while using a single API token.

## How We'll Evaluate Your Work

This isn't just about getting the right answer. We're excited to see how you approach the problem. Treat this as you would a production-ready feature.

  * We'll be looking for clean, well-structured, and testable code. Feel free to add dependencies or refactor the existing scaffold as you see fit.
  * How do you decide on your approach to meeting the performance and cost requirements? Documenting your thought process is a great way to share this.
  * A reliable service anticipates failure. How does your service behave if the pricing model is slow, or returns an error? Providing descriptive error messages to the end-user is a key part of a robust API.
  * We want to see how you work around constraints and navigate an existing codebase to deliver a solution.


## Minimum Deliverables

1.  A link to your Git repository containing the complete solution.
2.  Clear instructions in the `README.md` on how to build, test, and run your service.

We highly value seeing your thought process. A great submission will also include documentation (e.g., in the `README.md`) discussing the design choices you made. Consider outlining different approaches you considered, their potential tradeoffs, and a clear rationale for why you chose your final solution.

## Development Environment Setup

The project scaffold is a minimal Ruby on Rails application with a `/api/v1/pricing` endpoint. While you're free to configure your environment as you wish, this repository is pre-configured for a Docker-based workflow that supports live reloading for your convenience.

The provided `Dockerfile` builds a container with all necessary dependencies. Your local code is mounted directly into the container, so any changes you make on your machine will be reflected immediately. Your application will need to communicate with the external pricing model, which also runs in its own Docker container.

### Quick Start Guide

Here is a list of common commands for building, running, and interacting with the Dockerized environment.

```bash

# --- 1. Build & Run The Main Application ---
# Build and run the Docker compose
docker compose up -d --build

# --- 2. Test The Endpoint ---
# Send a sample request to your running service
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'

# --- 3. Run Tests ---
# Run the full test suite
docker compose exec interview-dev ./bin/rails test

# Run a specific test file
docker compose exec interview-dev ./bin/rails test test/controllers/pricing_controller_test.rb

# Run a specific test by name
docker compose exec interview-dev ./bin/rails test test/controllers/pricing_controller_test.rb -n test_should_get_pricing_with_all_parameters
```

Good luck, and we look forward to seeing what you build\!
