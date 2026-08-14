# Architecture

## What this lab does

This lab runs controlled attack simulations against systems that belong to the
lab.

The target systems send logs and security events to Elastic.

Elastic is used to search the logs, run detection rules, create alerts, and
show the results in Kibana.

## Main parts

The lab will have a few separate areas.

### Public side

This is the part a demo user can reach.

It will include:

- the demo web page
- read-only Kibana access

A demo user should only be able to run the tests I have already set up.

### Demo controller

The demo controller sits between the public site and CALDERA.

A user might send a request like:

    linux-discovery

The controller checks that the scenario is allowed.

If it is allowed, the controller starts the matching CALDERA test.

The user cannot send their own shell command, IP address, payload, or CALDERA
ability.

### CALDERA

CALDERA runs the attack simulations.

CALDERA will not be directly exposed to the internet.

Only the demo controller and admin systems should be able to reach it.

### Target systems

These are the systems CALDERA tests against.

They are part of the lab and should not be publicly reachable.

They will send security logs to Elastic.

### Elastic

Elastic receives the logs from the lab.

It will be used for:

- log storage
- searching
- detection rules
- alerts
- dashboards
- checking if a test was detected

## Basic flow

    Demo user
        |
        v
    Demo web page
        |
        v
    Demo controller
        |
        v
    CALDERA
        |
        v
    Lab target
        |
        v
    Elastic
        |
        v
    Kibana dashboard

## Main security rule

The public user chooses a test that already exists.

The public user does not create the attack.

For example, this is allowed:

    linux-discovery

Something like this should never be accepted:

    cat /etc/passwd

The public site is only a way to start approved lab tests.
