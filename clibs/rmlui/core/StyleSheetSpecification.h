#pragma once

#include <core/PropertyIdSet.h>
#include <core/PropertyDictionary.h>

namespace Rml {

class PropertyParser;

class StyleSheetSpecification {
public:
	static bool Initialise();
	static void Shutdown();
	static bool IsInheritedProperty(PropertyId id);
	static const Property* GetDefaultProperty(PropertyId id);
	static const PropertyIdSet& GetInheritedProperties();
	static bool ParsePropertyDeclaration(PropertyIdSet& set, const std::string& property_name);
	static bool ParsePropertyDeclaration(PropertyDictionary& dictionary, const std::string& property_name, const std::string& property_value);
};

}
