#include <core/StyleSheetNodeSelector.h>
#include <core/Element.h>
#include <core/Text.h>

namespace Rml::Selector {

template <typename T>
struct reversion_wrapper {
	auto begin() { return std::rbegin(iterable); }
	auto end () { return std::rend(iterable); }
	T& iterable;
};
template <typename T>
reversion_wrapper<T> reverse(T&& iterable) { return { iterable }; }

static bool IsNth(int a, int b, int count) {
	int x = count;
	x -= b;
	if (a != 0)
		x /= a;
	return (x >= 0 && x * a + b == count);
}

bool Empty(const Element* element, int, int) {
	for (const Element* child : element->Children()) {
		if (child->IsVisible())
			return false;
	}
	return true;
}

bool FirstChild(const Element* element, int, int) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	for (const Element* child : parent->Children()) {
		if (child == element)
			return true;
		return false;
	}
	return false;
}

bool FirstOfType(const Element* element, int, int) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	for (const Element* child : parent->Children()) {
		if (child == element)
			return true;
		if (child->GetTagName() == element->GetTagName() && child->IsVisible())
			return false;
	}
	return false;
}

bool LastChild(const Element* element, int, int) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	for (const Element* child : reverse(parent->Children())) {
		if (child == element)
			return true;
		return false;
	}
	return false;
}

bool LastOfType(const Element* element, int, int) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	for (const Element* child : reverse(parent->Children())) {
		if (child == element)
			return true;
		if (child->GetTagName() == element->GetTagName() && child->IsVisible())
			return false;
	}
	return false;
}

bool NthChild(const Element* element, int a, int b) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	int element_index = 1;
	for (const Element* child : parent->Children()) {
		if (child == element)
			break;
		if (!child->IsVisible())
			continue;
		element_index++;
	}
	return IsNth(a, b, element_index);
}

bool NthLastChild(const Element* element, int a, int b) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	int element_index = 1;
	for (const Element* child : reverse(parent->Children())) {
		if (child == element)
			break;
		if (!child->IsVisible())
			continue;
		element_index++;
	}
	return IsNth(a, b, element_index);
}

bool NthLastOfType(const Element* element, int a, int b) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	int element_index = 1;
	for (const Element* child : reverse(parent->Children())) {
		if (child == element)
			break;
		if (child->GetTagName() != element->GetTagName() || !child->IsVisible())
			continue;
		element_index++;
	}
	return IsNth(a, b, element_index);
}

bool NthOfType(const Element* element, int a, int b) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	int element_index = 1;
	for (const Element* child : parent->Children()) {
		if (child == element)
			break;
		if (child->GetTagName() != element->GetTagName() || !child->IsVisible())
			continue;
		element_index++;
	}
	return IsNth(a, b, element_index);
}

bool OnlyChild(const Element* element, int, int) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	for (const Element* child : parent->Children()) {
		if (child == element)
			continue;
		if (!child->IsVisible())
			continue;
		return false;
	}
	return true;
}

bool OnlyOfType(const Element* element, int, int) {
	Element* parent = element->GetParentNode();
	if (parent == nullptr)
		return false;
	for (const Element* child : parent->Children()) {
		if (child == element)
			continue;
		if (child->GetTagName() != element->GetTagName() || !child->IsVisible())
			continue;
		return false;
	}
	return true;
}

}
