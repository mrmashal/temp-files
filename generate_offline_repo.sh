#!/bin/bash
set -euo pipefail

# ============================================================================
# Telegram Android Offline Repository Generator
# ============================================================================
# Usage: ./generate_offline_repo.sh <segment>
# Segments: buildsrc, main, plugins, all
# ============================================================================

SEGMENT="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_BASE="${SCRIPT_DIR}/offline-repo"
LOG_FILE="${SCRIPT_DIR}/offline-repo-generation.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# Initialize
# ============================================================================
log "Starting Telegram Android Offline Repository Generator"
log "Segment: $SEGMENT"
log "Working directory: $SCRIPT_DIR"
log "Repository base: $REPO_BASE"

# Create base repo structure
mkdir -p "$REPO_BASE"

# ============================================================================
# Segment 1: BuildSrc Dependencies
# ============================================================================
generate_buildsrc_segment() {
    log "=========================================="
    log "SEGMENT 1: BuildSrc Dependencies"
    log "=========================================="
    
    SEGMENT_DIR="${REPO_BASE}-buildsrc"
    GRADLE_HOME="${SCRIPT_DIR}/.gradle-buildsrc"
    
    mkdir -p "$SEGMENT_DIR"
    mkdir -p "$GRADLE_HOME"
    
    # Create gradle.properties for buildSrc
    cat > "$GRADLE_HOME/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx768m -XX:MaxMetaspaceSize=384m -XX:+UseG1GC
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.caching=false
org.gradle.configureondemand=false
EOF
    
    log "Creating isolated buildSrc project for dependency resolution..."
    
    BUILDSRC_TEMP="${SCRIPT_DIR}/.buildsrc-temp"
    rm -rf "$BUILDSRC_TEMP"
    mkdir -p "$BUILDSRC_TEMP/buildSrc/src/main/kotlin/com/example"
    
    # Create buildSrc/build.gradle.kts
    cat > "$BUILDSRC_TEMP/buildSrc/build.gradle.kts" <<'EOF'
plugins {
    `kotlin-dsl`
}

gradlePlugin {
    plugins {
        register("testGenerator") {
            id = "test-generator"
            implementationClass = "com.example.TestGeneratorPlugin"
        }
    }
}

repositories {
    google()
    mavenCentral()
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
        apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
    }
}

dependencies {
    compileOnly(gradleApi())
    implementation("com.squareup.moshi:moshi:1.15.0")
    implementation("com.squareup.moshi:moshi-kotlin:1.15.0")
    implementation("com.github.javaparser:javaparser-core:3.25.4")
    implementation("com.squareup:kotlinpoet:1.15.0")
}
EOF
    
    # Create dummy plugin class
    cat > "$BUILDSRC_TEMP/buildSrc/src/main/kotlin/com/example/TestGeneratorPlugin.kt" <<'EOF'
package com.example

import org.gradle.api.Plugin
import org.gradle.api.Project

class TestGeneratorPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        // Dummy plugin
    }
}
EOF
    
    # Create root build.gradle.kts (minimal)
    cat > "$BUILDSRC_TEMP/build.gradle.kts" <<'EOF'
// Root project
EOF
    
    # Create settings.gradle.kts
    cat > "$BUILDSRC_TEMP/settings.gradle.kts" <<'EOF'
rootProject.name = "telegram-buildsrc-resolver"
EOF
    
    log "Resolving buildSrc dependencies without building..."
    
    cd "$BUILDSRC_TEMP"
    
    # Use --dry-run to resolve dependencies without actual compilation
    GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew buildSrc:dependencies \
        --refresh-dependencies \
        --no-daemon \
        --stacktrace 2>&1 | tee -a "$LOG_FILE" || {
        log_warn "Initial dependency resolution had issues, trying compileClasspath..."
    }
    
    # Resolve specific configurations
    GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew buildSrc:dependencies \
        --configuration compileClasspath \
        --no-daemon \
        --stacktrace 2>&1 | tee -a "$LOG_FILE" || true
    
    GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew buildSrc:dependencies \
        --configuration runtimeClasspath \
        --no-daemon \
        --stacktrace 2>&1 | tee -a "$LOG_FILE" || true
    
    log "Copying buildSrc dependencies to segment directory..."
    
    # Copy caches
    if [ -d "$GRADLE_HOME/caches" ]; then
        cp -r "$GRADLE_HOME/caches" "$SEGMENT_DIR/" 2>&1 | tee -a "$LOG_FILE"
        log_success "Copied caches directory"
    fi
    
    # Copy wrapper
    if [ -d "$GRADLE_HOME/wrapper" ]; then
        cp -r "$GRADLE_HOME/wrapper" "$SEGMENT_DIR/" 2>&1 | tee -a "$LOG_FILE"
        log_success "Copied wrapper directory"
    fi
    
    # Create metadata
    cat > "$SEGMENT_DIR/segment-info.txt" <<EOF
Segment: buildsrc
Generated: $(date)
Description: BuildSrc dependencies including Kotlin DSL, Moshi, JavaParser, KotlinPoet
EOF
    
    log_success "BuildSrc segment generated at: $SEGMENT_DIR"
    du -sh "$SEGMENT_DIR" 2>&1 | tee -a "$LOG_FILE"
    
    cd "$SCRIPT_DIR"
}

# ============================================================================
# Segment 2: Main Project Dependencies
# ============================================================================
generate_main_segment() {
    log "=========================================="
    log "SEGMENT 2: Main Project Dependencies"
    log "=========================================="
    
    SEGMENT_DIR="${REPO_BASE}-main"
    GRADLE_HOME="${SCRIPT_DIR}/.gradle-main"
    
    mkdir -p "$SEGMENT_DIR"
    mkdir -p "$GRADLE_HOME"
    
    # Create gradle.properties for main project
    cat > "$GRADLE_HOME/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx768m -XX:MaxMetaspaceSize=384m -XX:+UseG1GC
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.caching=false
org.gradle.configureondemand=false
android.useAndroidX=true
android.enableJetifier=false
EOF
    
    log "Resolving main project dependencies..."
    
    cd "$SCRIPT_DIR"
    
    # Resolve dependencies for all configurations without building
    GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew dependencies \
        --refresh-dependencies \
        --no-daemon \
        --stacktrace 2>&1 | tee -a "$LOG_FILE" || {
        log_warn "Main dependencies resolution had issues, continuing..."
    }
    
    # Try to resolve specific module dependencies
    log "Resolving TMessagesProj dependencies..."
    GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew :TMessagesProj:dependencies \
        --no-daemon \
        --stacktrace 2>&1 | tee -a "$LOG_FILE" || true
    
    log "Resolving TMessagesProj_App dependencies..."
    GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew :TMessagesProj_App:dependencies \
        --no-daemon \
        --stacktrace 2>&1 | tee -a "$LOG_FILE" || true
    
    # Check for Standalone module
    if [ -d "TMessagesProj_Standalone" ] || grep -q "TMessagesProj_Standalone" settings.gradle* 2>/dev/null; then
        log "Resolving TMessagesProj_Standalone dependencies..."
        GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew :TMessagesProj_Standalone:dependencies \
            --no-daemon \
            --stacktrace 2>&1 | tee -a "$LOG_FILE" || true
    fi
    
    log "Copying main project dependencies to segment directory..."
    
    # Copy caches (excluding buildSrc-specific caches if they exist)
    if [ -d "$GRADLE_HOME/caches" ]; then
        cp -r "$GRADLE_HOME/caches" "$SEGMENT_DIR/" 2>&1 | tee -a "$LOG_FILE"
        log_success "Copied caches directory"
    fi
    
    # Copy wrapper
    if [ -d "$GRADLE_HOME/wrapper" ]; then
        cp -r "$GRADLE_HOME/wrapper" "$SEGMENT_DIR/" 2>&1 | tee -a "$LOG_FILE"
        log_success "Copied wrapper directory"
    fi
    
    # Create metadata
    cat > "$SEGMENT_DIR/segment-info.txt" <<EOF
Segment: main
Generated: $(date)
Description: Main project dependencies including TMessagesProj, TMessagesProj_App, and Standalone module
EOF
    
    log_success "Main segment generated at: $SEGMENT_DIR"
    du -sh "$SEGMENT_DIR" 2>&1 | tee -a "$LOG_FILE"
}

# ============================================================================
# Segment 3: Android/Gradle Plugins
# ============================================================================
generate_plugins_segment() {
    log "=========================================="
    log "SEGMENT 3: Android/Gradle Plugins"
    log "=========================================="
    
    SEGMENT_DIR="${REPO_BASE}-plugins"
    GRADLE_HOME="${SCRIPT_DIR}/.gradle-plugins"
    
    mkdir -p "$SEGMENT_DIR"
    mkdir -p "$GRADLE_HOME"
    
    # Create gradle.properties for plugins
    cat > "$GRADLE_HOME/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx768m -XX:MaxMetaspaceSize=384m -XX:+UseG1GC
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.caching=false
EOF
    
    log "Creating plugin resolution project..."
    
    PLUGIN_TEMP="${SCRIPT_DIR}/.plugin-temp"
    rm -rf "$PLUGIN_TEMP"
    mkdir -p "$PLUGIN_TEMP"
    
    # Detect AGP and Kotlin versions from the actual project
    AGP_VERSION="8.1.4"
    KOTLIN_VERSION="1.9.22"
    
    if [ -f "build.gradle.kts" ]; then
        AGP_DETECTED=$(grep -oP 'com\.android\.tools\.build:gradle:\K[0-9.]+' build.gradle.kts | head -1 || echo "")
        KOTLIN_DETECTED=$(grep -oP 'org\.jetbrains\.kotlin:kotlin-gradle-plugin:\K[0-9.]+' build.gradle.kts | head -1 || echo "")
        [ -n "$AGP_DETECTED" ] && AGP_VERSION="$AGP_DETECTED"
        [ -n "$KOTLIN_DETECTED" ] && KOTLIN_VERSION="$KOTLIN_DETECTED"
    elif [ -f "build.gradle" ]; then
        AGP_DETECTED=$(grep -oP 'com\.android\.tools\.build:gradle:\K[0-9.]+' build.gradle | head -1 || echo "")
        KOTLIN_DETECTED=$(grep -oP 'org\.jetbrains\.kotlin:kotlin-gradle-plugin:\K[0-9.]+' build.gradle | head -1 || echo "")
        [ -n "$AGP_DETECTED" ] && AGP_VERSION="$AGP_DETECTED"
        [ -n "$KOTLIN_DETECTED" ] && KOTLIN_VERSION="$KOTLIN_DETECTED"
    fi
    
    log "Detected AGP version: $AGP_VERSION"
    log "Detected Kotlin version: $KOTLIN_VERSION"
    
    # Create settings.gradle.kts
    cat > "$PLUGIN_TEMP/settings.gradle.kts" <<EOF
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "telegram-plugin-resolver"
EOF
    
    # Create build.gradle.kts with all plugins
    cat > "$PLUGIN_TEMP/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "$AGP_VERSION" apply false
    id("com.android.library") version "$AGP_VERSION" apply false
    kotlin("android") version "$KOTLIN_VERSION" apply false
    kotlin("jvm") version "$KOTLIN_VERSION" apply false
}

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:$AGP_VERSION")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$KOTLIN_VERSION")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
EOF
    
    log "Resolving plugin dependencies..."
    
    cd "$PLUGIN_TEMP"
    
    # Resolve buildscript classpath
    GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew buildEnvironment \
        --refresh-dependencies \
        --no-daemon \
        --stacktrace 2>&1 | tee -a "$LOG_FILE" || {
        log_warn "Plugin resolution had issues, continuing..."
    }
    
    # Force download of plugins
    GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew dependencies \
        --no-daemon \
        --stacktrace 2>&1 | tee -a "$LOG_FILE" || true
    
    log "Copying plugin dependencies to segment directory..."
    
    # Copy caches
    if [ -d "$GRADLE_HOME/caches" ]; then
        cp -r "$GRADLE_HOME/caches" "$SEGMENT_DIR/" 2>&1 | tee -a "$LOG_FILE"
        log_success "Copied caches directory"
    fi
    
    # Copy wrapper
    if [ -d "$GRADLE_HOME/wrapper" ]; then
        cp -r "$GRADLE_HOME/wrapper" "$SEGMENT_DIR/" 2>&1 | tee -a "$LOG_FILE"
        log_success "Copied wrapper directory"
    fi
    
    # Create metadata
    cat > "$SEGMENT_DIR/segment-info.txt" <<EOF
Segment: plugins
Generated: $(date)
Description: Android Gradle Plugin ($AGP_VERSION), Kotlin Plugin ($KOTLIN_VERSION), and related dependencies
EOF
    
    log_success "Plugins segment generated at: $SEGMENT_DIR"
    du -sh "$SEGMENT_DIR" 2>&1 | tee -a "$LOG_FILE"
    
    cd "$SCRIPT_DIR"
}

# ============================================================================
# Main Execution
# ============================================================================

case "$SEGMENT" in
    buildsrc)
        generate_buildsrc_segment
        ;;
    main)
        generate_main_segment
        ;;
    plugins)
        generate_plugins_segment
        ;;
    all)
        generate_buildsrc_segment
        log ""
        generate_main_segment
        log ""
        generate_plugins_segment
        ;;
    *)
        log_error "Invalid segment: $SEGMENT"
        log "Valid segments: buildsrc, main, plugins, all"
        exit 1
        ;;
esac

# ============================================================================
# Summary
# ============================================================================
log ""
log "=========================================="
log "Generation Complete"
log "=========================================="
log "Generated segments:"
[ -d "${REPO_BASE}-buildsrc" ] && log "  - ${REPO_BASE}-buildsrc ($(du -sh ${REPO_BASE}-buildsrc | cut -f1))"
[ -d "${REPO_BASE}-main" ] && log "  - ${REPO_BASE}-main ($(du -sh ${REPO_BASE}-main | cut -f1))"
[ -d "${REPO_BASE}-plugins" ] && log "  - ${REPO_BASE}-plugins ($(du -sh ${REPO_BASE}-plugins | cut -f1))"
log ""
log "Next steps:"
log "1. Compress each segment: tar -czf offline-repo-<segment>.tar.gz offline-repo-<segment>/"
log "2. Transfer to offline machine"
log "3. Extract all segments: tar -xzf offline-repo-<segment>.tar.gz"
log "4. Merge Gradle homes: GRADLE_USER_HOME=/path/to/merged/gradle"
log "   - Copy all caches/* from each segment to merged location"
log "   - Copy wrapper/* from any segment to merged location"
log ""
log "Log file: $LOG_FILE"
log_success "All done!"
