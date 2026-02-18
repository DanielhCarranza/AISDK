//
//  V1Compatibility.swift
//  AISDK
//
//  Backward-compatibility typealiases for v1 consumers migrating to v2.
//  These allow v1 code to compile against v2 without changes for renamed types.
//

import Foundation

// MARK: - Type Renames

/// v1 `ChatMessage` → v2 `LegacyChatMessage`
public typealias ChatMessage = LegacyChatMessage

/// v1 `ResearcherAgentState` → v2 `ResearcherLegacyAgentState`
public typealias ResearcherAgentState = ResearcherLegacyAgentState

/// v1 `AgentState` → v2 `LegacyAgentState`
public typealias AgentState = LegacyAgentState

/// v1 `Message` → v2 `LegacyMessage`
public typealias Message = LegacyMessage
