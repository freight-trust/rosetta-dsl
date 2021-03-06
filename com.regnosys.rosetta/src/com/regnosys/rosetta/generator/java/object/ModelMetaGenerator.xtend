package com.regnosys.rosetta.generator.java.object

import com.google.common.collect.Sets
import com.google.inject.Inject
import com.regnosys.rosetta.RosettaExtensions
import com.regnosys.rosetta.generator.java.RosettaJavaPackages
import com.regnosys.rosetta.generator.java.qualify.QualifyFunctionGenerator
import com.regnosys.rosetta.generator.java.rule.ChoiceRuleGenerator
import com.regnosys.rosetta.generator.java.rule.DataRuleGenerator
import com.regnosys.rosetta.generator.java.util.ImportGenerator
import com.regnosys.rosetta.generator.java.util.ImportManagerExtension
import com.regnosys.rosetta.generator.java.util.JavaNames
import com.regnosys.rosetta.generator.util.RosettaFunctionExtensions
import com.regnosys.rosetta.rosetta.RosettaCallable
import com.regnosys.rosetta.rosetta.RosettaCallableCall
import com.regnosys.rosetta.rosetta.RosettaChoiceRule
import com.regnosys.rosetta.rosetta.RosettaClass
import com.regnosys.rosetta.rosetta.RosettaDataRule
import com.regnosys.rosetta.rosetta.RosettaEvent
import com.regnosys.rosetta.rosetta.RosettaExpression
import com.regnosys.rosetta.rosetta.RosettaFeatureCall
import com.regnosys.rosetta.rosetta.RosettaModel
import com.regnosys.rosetta.rosetta.RosettaNamed
import com.regnosys.rosetta.rosetta.RosettaProduct
import com.regnosys.rosetta.rosetta.RosettaRegularAttribute
import com.regnosys.rosetta.rosetta.RosettaRootElement
import com.regnosys.rosetta.rosetta.simple.Condition
import com.regnosys.rosetta.rosetta.simple.Data
import com.regnosys.rosetta.rosetta.simple.Function
import com.regnosys.rosetta.utils.RosettaConfigExtension
import com.rosetta.model.lib.annotations.RosettaMeta
import com.rosetta.model.lib.meta.RosettaMetaData
import com.rosetta.model.lib.qualify.QualifyFunctionFactory
import com.rosetta.model.lib.qualify.QualifyResult
import com.rosetta.model.lib.validation.Validator
import com.rosetta.model.lib.validation.ValidatorWithArg
import java.util.Arrays
import java.util.List
import java.util.Set
import org.eclipse.xtend2.lib.StringConcatenationClient
import org.eclipse.xtext.generator.IFileSystemAccess2

import static com.regnosys.rosetta.generator.java.util.ModelGeneratorUtil.*

import static extension com.regnosys.rosetta.generator.util.RosettaAttributeExtensions.cardinalityIsListValue

class ModelMetaGenerator {

	@Inject extension ImportManagerExtension
	@Inject extension RosettaExtensions
	@Inject RosettaConfigExtension confExt
	@Inject RosettaFunctionExtensions funcExt
	
	def generate(RosettaJavaPackages packages, IFileSystemAccess2 fsa, List<RosettaRootElement> elements, String version) {
		elements.filter(RosettaClass).forEach [ RosettaClass rosettaClass |
			val className = '''«rosettaClass.name»Meta'''
			fsa.generateFile('''«packages.model.meta.directoryName»/«className».java''',
				metaClass(packages, className, rosettaClass, elements, version))
		]
	}
	
	def generate(JavaNames names, IFileSystemAccess2 fsa, Data data, String version, Set<RosettaModel> models) {
		val className = '''«data.name»Meta'''
		
		val classBody = tracImports(data.metaClassBody(names, className, version, models))
		val javaFileContents = '''
			package «names.packages.model.meta.name»;
			
			«FOR imp : classBody.imports»
				import «imp»;
			«ENDFOR»
			«FOR imp : classBody.staticImports»
				import static «imp»;
			«ENDFOR»
			
			«classBody.toString»
		'''
		fsa.generateFile('''«names.packages.model.meta.directoryName»/«className».java''', javaFileContents)
	}
	
	private def StringConcatenationClient metaClassBody(Data c, JavaNames javaNames, String className, String version, Set<RosettaModel> models) {
		val dataClass = javaNames.toJavaType(c)
		val qualifierFuncs = qualifyFuncs(c, javaNames, models)
		'''
			«emptyJavadocWithVersion(version)»
			@«RosettaMeta»(model=«dataClass».class)
			public class «className» implements «RosettaMetaData»<«dataClass»> {
			
				@Override
				public «List»<«Validator»<? super «dataClass»>> dataRules() {
					return «Arrays».asList(
						«FOR r : conditionRules(c, c.conditions)[!isChoiceRuleCondition] SEPARATOR ','»
							new «javaNames.packages.model.dataRule.name».«DataRuleGenerator.dataRuleClassName(r.ruleName)»()
						«ENDFOR»
					);
				}
			
				@Override
				public «List»<«Validator»<? super «dataClass»>> choiceRuleValidators() {
					return Arrays.asList(
						«FOR r : conditionRules(c, c.conditions)[isChoiceRuleCondition] SEPARATOR ','»
							new «javaNames.packages.model.choiceRule.name».«ChoiceRuleGenerator.choiceRuleClassName(r.ruleName)»()
						«ENDFOR»
					);
				}

				@Override
				public «List»<«java.util.function.Function»<? super «dataClass», «QualifyResult»>> getQualifyFunctions() {
					return Arrays.asList(
						«FOR qf : qualifyFunctions(javaNames.packages, c.model.elements, c) SEPARATOR ','»
							new «qf.javaPackage».«qf.functionName»()
						«ENDFOR»
					);
				}
				«IF !qualifierFuncs.nullOrEmpty»
				
				@Override
				public «List»<«java.util.function.Function»<? super «dataClass», «QualifyResult»>> getQualifyFunctions(«QualifyFunctionFactory» factory) {
					return Arrays.asList(
						«FOR qf : qualifierFuncs SEPARATOR ','»
							factory.create(«javaNames.toJavaType(qf)».class)
						«ENDFOR»
					);
				}
				«ENDIF»
				
				@Override
				public «Validator»<? super «dataClass»> validator() {
					return new «javaNames.packages.model.typeValidation.name».«dataClass»Validator();
				}
				
				@Override
				public «ValidatorWithArg»<? super «dataClass», String> onlyExistsValidator() {
					return new «javaNames.packages.model.existsValidation.name».«ModelObjectGenerator.onlyExistsValidatorName(c)»();
				}
			}
		'''
	}
	
	private def Set<Function> qualifyFuncs(Data type, JavaNames names, Set<RosettaModel> models) {
		if(!confExt.isRootEventOrProduct(type)) {
			return emptySet
		}
		val funcs = models.flatMap[elements].filter(Function).toSet
		return funcs.filter[funcExt.isQualifierFunctionFor(it,type)].toSet
	}
	
	private def metaClass(RosettaJavaPackages packages, String className, RosettaClass c,
		List<RosettaRootElement> elements, String version) {
		val imports = new ImportGenerator(packages)
		imports.addMeta(c)

		'''
			package «packages.model.meta.name»;
			
			«FOR importClass : imports.imports.filter[imports.isImportable(it)]»
				import «importClass»;
			«ENDFOR»
			
			«FOR importClass : imports.staticImports»
				import static «importClass».*;
			«ENDFOR»
			
			«emptyJavadocWithVersion(version)»
			@RosettaMeta(model=«c.name».class)
			public class «className» implements RosettaMetaData<«c.name»> {
			
				@Override
				public List<Validator<? super «c.name»>> dataRules() {
					return Arrays.asList(
						«FOR r : dataRules(elements, c) SEPARATOR ','»
							new «packages.model.dataRule.name».«DataRuleGenerator.dataRuleClassName(r.ruleName)»()
						«ENDFOR»
					);
				}
			
				@Override
				public List<Validator<? super «c.name»>> choiceRuleValidators() {
					return Arrays.asList(
						«IF c.oneOf»
							new «packages.model.choiceRule.name».«ChoiceRuleGenerator.oneOfRuleClassName(c.name)»()
						«ENDIF»
						«FOR r : choiceRules(elements, c) SEPARATOR ','»
							new «packages.model.choiceRule.name».«ChoiceRuleGenerator.choiceRuleClassName(r.ruleName)»()
						«ENDFOR»
					);
				}

				@Override
				public List<Function<? super «c.name», QualifyResult>> getQualifyFunctions() {
					return Arrays.asList(
						«FOR qf : qualifyFunctions(packages, elements, c) SEPARATOR ','»
							new «qf.javaPackage».«qf.functionName»()
						«ENDFOR»
					);
				}
				
				@Override
				public Validator<? super «c.name»> validator() {
					return new «packages.model.typeValidation.name».«c.name»Validator();
				}
				
				@Override
				public ValidatorWithArg<? super «c.name», String> onlyExistsValidator() {
					return new «packages.model.existsValidation.name».«ModelObjectGenerator.onlyExistsValidatorName(c)»();
				}
			}
		'''
	}

	def isList(RosettaExpression call) {
		switch (call) {
			RosettaCallableCall:
				return false
			RosettaFeatureCall: {
				return (call.feature as RosettaRegularAttribute).cardinalityIsListValue
			}
		}
	}

	def CharSequence getCreate(RosettaExpression call) {
		switch (call) {
			RosettaCallableCall:
				return ""
			RosettaFeatureCall: {
				val list = isList(call)
				return '''«getCreate(call.receiver)».getOrCreate«call.feature.name.toFirstUpper»(«IF list»i«ENDIF»)'''
			}
		}
	}

	def CharSequence getOutStartClass(RosettaExpression expr) {
		switch (expr) {
			RosettaFeatureCall:
				getOutStartClass(expr.receiver)
			RosettaCallableCall: {
				val callable = expr.callable as RosettaClass;
				return callable.name
			}
		}
	}

	protected def static List<ClassRule> choiceRules(List<RosettaRootElement> elements, RosettaClass thisClass) {
		val choiceRules = elements.filter(RosettaChoiceRule)
		val classRules = choiceRules.map[new ClassRule(scope.name, name)]
		return classRules.filter[it.className === thisClass.name].toList
	}
	
	protected def static List<ClassRule> dataRules(List<RosettaRootElement> elements, RosettaClass thisClass) {
		val dataRuleMappingSet = Sets.newLinkedHashSet
		elements.filter(RosettaDataRule).forEach [ dataRule |
			val dataRuleWhen = dataRule.when
			// TODO we need some kind of expansion for alias calls here
			val rosettaClasses = dataRuleWhen.eAllContents.filter(RosettaCallableCall).map[callable].filter(
				RosettaClass)
			val classRules = rosettaClasses.map[new ClassRule(name, dataRule.name)]
			dataRuleMappingSet.addAll(classRules.toSet)
		]
		return dataRuleMappingSet.filter[it.className === thisClass.name].toList
	}
	
	private def List<ClassRule> conditionRules(Data d, List<Condition> elements, (Condition)=>boolean filter) {
		return elements.filter(filter).map[new ClassRule((it.eContainer as RosettaNamed).getName, it.conditionName(d))].toList
	}

	@org.eclipse.xtend.lib.annotations.Data
	static class ClassRule {
		String className;
		String ruleName;
	}

	
	private def List<QualifyFunction> qualifyFunctions(RosettaJavaPackages packages, List<RosettaRootElement> elements,
		RosettaCallable thisClass) {
		val allQualifyFns = Sets.newLinkedHashSet
		val superClasses 
			= if(thisClass instanceof RosettaClass)
				thisClass.allSuperTypes.map[name].toList
			else if(thisClass instanceof Data)
				thisClass.allSuperTypes.map[name].toList
				
		// TODO create public constant with list of qualifiable classes / packages
		allQualifyFns.addAll(
			getQualifyFunctionsForRosettaClass(RosettaEvent, packages.model.qualifyEvent.name, elements))
		allQualifyFns.addAll(
			getQualifyFunctionsForRosettaClass(RosettaProduct, packages.model.qualifyProduct.name, elements))
		return allQualifyFns.filter[superClasses.contains(it.className)].toList
	}

	private def <T extends RosettaRootElement & RosettaNamed> getQualifyFunctionsForRosettaClass(Class<T> clazz,
		String javaPackage, List<RosettaRootElement> elements) {
		val qualifyFns = Sets.newLinkedHashSet
		elements.filter(clazz).forEach [
			val rosettaClass = getRosettaClass(it)
			val functionName = QualifyFunctionGenerator.getIsFunctionClassName(it.name)
			rosettaClass.ifPresent [
				qualifyFns.add(new QualifyFunction(it.name, javaPackage, functionName))
			]
		]
		return qualifyFns
	}

	private def getRosettaClass(RosettaRootElement element) {
		val rosettaClasses = newHashSet
		element.eAllContents.filter(RosettaCallableCall).forEach [
			collectRootCalls(it, [if(it instanceof RosettaClass || it instanceof Data) rosettaClasses.add(it)])
		]
		return rosettaClasses.stream.findAny
	}

	@org.eclipse.xtend.lib.annotations.Data
	static class QualifyFunction {
		String className;
		String javaPackage;
		String functionName;
	}
}
