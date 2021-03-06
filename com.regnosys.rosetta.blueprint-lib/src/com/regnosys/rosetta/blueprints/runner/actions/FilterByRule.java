package com.regnosys.rosetta.blueprints.runner.actions;

import com.regnosys.rosetta.blueprints.BlueprintInstance;
import com.regnosys.rosetta.blueprints.runner.CaptureDownstream;
import com.regnosys.rosetta.blueprints.runner.data.GroupableData;
import com.regnosys.rosetta.blueprints.runner.nodes.NamedNode;
import com.regnosys.rosetta.blueprints.runner.nodes.ProcessorNode;

import java.util.Collections;
import java.util.Optional;

public class FilterByRule<I, K extends Comparable<K>> extends NamedNode implements ProcessorNode<I, I, K> {

	BlueprintInstance<? super I, Boolean, K, K> filter;
	CaptureDownstream<Boolean, K> downstream;
	
	public FilterByRule(String uri, String label, BlueprintInstance<? super I, Boolean, K, K> filter) {
		super(uri, label);
		this.filter = filter;
		downstream = new CaptureDownstream<>();
		filter.addDownstreams(downstream);
	}

	@Override
	public <T extends I> Optional<GroupableData<I, K>> process(GroupableData<T, K> input) {
		filter.process(input);
		boolean result = downstream.isTruthy(input.getKey());
		if (result) {
			return Optional.of(input.withIssues(input.getData(), Collections.emptyList(), this));
		}
		return Optional.empty();
	}

}
