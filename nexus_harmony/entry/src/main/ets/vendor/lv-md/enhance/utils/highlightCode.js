export function highlightCodeToJSON(code, colors = {}, language = "javascript") {
    // ------- 颜色表 -------
    const defaultColors = {
        keyword: '#9333ea', // 关键字
        method: '#ff206fcd', // 方法名
        type: '#9333ea', // 类型
        modifier: '#4169e1', // 修饰符
        constant: '#8b0000', // 常量
        variable: '#333333', // 变量
        operator: '#b22222', // 运算符
        punctuation: '#666666', // 标点
        brace: '#F56C6C', // 括号
        bigBrace: '',
        string: '#8475F5', // 字符串
        number: '#A9D43E', // 数字
        boolean: '#ffad50ff', // 布尔值
        nullish: '#E2DA75', // 空值
        promise: '#ffbe00be', // Promise
        tag: '#008b8b', // HTML标签
        attrName: '#ffc65e0a', // 属性名
        attrValue: '#ff50641c', // 属性值
        doctype: '#ff8c00', // 文档声明
        comment: '#ff787983', // 注释
        decorator: '#ff69b4', // ArkTS 装饰器
        component: '#20b2aa', // ArkTS UI组件
        normal: '#ff535862'         // 普通文本
    };
    const c = { ...defaultColors, ...colors };

    // ------- 多语言规则 -------
    const languageRules = {
        javascript: {
            keywords: ['function', 'return', 'if', 'else', 'for', 'while', 'switch', 'case', 'break', 'continue',
                'const', 'let', 'var', 'new', 'this', 'super', 'extends', 'class', 'interface', 'import', 'export',
                'try', 'catch', 'finally', 'throw', 'typeof', 'instanceof', 'in', 'of', 'delete'],
            types: ['Promise', 'Map', 'Set', 'String', 'Number', 'Boolean', 'Object', 'Array', 'void', 'any'],
            booleans: ['true', 'false'],
            nullish: ['null', 'undefined'],
            extra: ['async', 'await', 'resolve', 'reject']
        },
        python: {
            keywords: ['def', 'return', 'if', 'elif', 'else', 'for', 'while', 'break', 'continue', 'class', 'import',
                'from',
                'try', 'except', 'finally', 'raise', 'with', 'as', 'lambda', 'pass', 'yield', 'in', 'is', 'and', 'or',
                'not'],
            types: ['int', 'float', 'str', 'list', 'dict', 'set', 'bool', 'object'],
            booleans: ['True', 'False'],
            nullish: ['None'],
            extra: []
        },
        java: {
            keywords: ['class', 'interface', 'extends', 'implements', 'public', 'private', 'protected', 'static',
                'final',
                'void', 'return', 'if', 'else', 'for', 'while', 'switch', 'case', 'break', 'continue', 'try', 'catch',
                'finally', 'throw', 'throws', 'import', 'package', 'new', 'this', 'super'],
            types: ['int', 'float', 'double', 'char', 'boolean', 'String', 'Object', 'List', 'Map', 'Set'],
            booleans: ['true', 'false'],
            nullish: ['null'],
            extra: []
        },
        cpp: {
            keywords: ['class', 'struct', 'template', 'typename', 'if', 'else', 'for', 'while', 'do', 'switch', 'case',
                'break',
                'continue', 'return', 'public', 'private', 'protected', 'virtual', 'override', 'namespace', 'using',
                'include', 'new', 'delete'],
            types: ['int', 'float', 'double', 'char', 'bool', 'void', 'string', 'vector', 'map', 'set'],
            booleans: ['true', 'false'],
            nullish: ['nullptr'],
            extra: []
        },
        html: {
            keywords: [],
            types: [],
            booleans: [],
            nullish: [],
            extra: []
        },
        css: {
            keywords: ['color', 'background', 'font', 'display', 'position', 'flex', 'grid', 'margin', 'padding',
                'border',
                'width', 'height', 'top', 'left', 'right', 'bottom'],
            types: [],
            booleans: [],
            nullish: [],
            extra: []
        },
        sql: {
            keywords: ['SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'JOIN', 'LEFT',
                'RIGHT',
                'INNER', 'OUTER', 'ON', 'AS', 'DISTINCT', 'GROUP', 'BY', 'ORDER', 'LIMIT', 'OFFSET', 'HAVING'],
            types: ['INT', 'VARCHAR', 'TEXT', 'DATE', 'BOOLEAN', 'FLOAT', 'DOUBLE', 'DECIMAL'],
            booleans: ['TRUE', 'FALSE'],
            nullish: ['NULL'],
            extra: []
        },
        json: {
            keywords: [],
            types: [],
            booleans: ['true', 'false'],
            nullish: ['null'],
            extra: []
        },
        arkts: {
            keywords: ['struct', 'interface', 'extends', 'super', 'return', 'if', 'else', 'for', 'while', 'switch',
                'case',
                'break', 'continue', 'try', 'catch', 'finally', 'throw', 'import', 'export', 'async', 'await', 'new',
                'this', 'let', 'const', 'var', 'public', 'private', 'protected'],
            types: ['string', 'number', 'boolean', 'void', 'any', 'object', 'Array', 'Promise'],
            booleans: ['true', 'false'],
            nullish: ['null', 'undefined'],
            components: ['Column', 'Row', 'Text', 'Button', 'Image', 'List', 'ListItem', 'Stack',
                'Grid', 'GridItem', 'Scroll', 'TextInput', 'Toggle', 'Slider', 'Progress',
                'Checkbox', 'Radio', 'Form', 'Navigator', 'Divider'],
            decorators: ['@State', '@Local', '@Prop', '@Provide', '@Consume',
                '@StorageLink', '@Link', '@Builder', '@Component', '@Entry', '@Observed', '@Preview']
        }
    };

    // -------- Default：合并所有语言规则 --------
    languageRules.default = {
        keywords: Array.from(new Set([
            ...languageRules.javascript.keywords,
            ...languageRules.python.keywords,
            ...languageRules.java.keywords,
            ...languageRules.cpp.keywords,
            ...languageRules.css.keywords,
            ...languageRules.sql.keywords,
            ...languageRules.arkts.keywords
        ])),
        types: Array.from(new Set([
            ...languageRules.javascript.types,
            ...languageRules.python.types,
            ...languageRules.java.types,
            ...languageRules.cpp.types,
            ...languageRules.sql.types,
            ...languageRules.arkts.types
        ])),
        booleans: Array.from(new Set([
            ...languageRules.javascript.booleans,
            ...languageRules.python.booleans,
            ...languageRules.java.booleans,
            ...languageRules.cpp.booleans,
            ...languageRules.sql.booleans,
            ...languageRules.json.booleans,
            ...languageRules.arkts.booleans
        ])),
        nullish: Array.from(new Set([
            ...languageRules.javascript.nullish,
            ...languageRules.python.nullish,
            ...languageRules.java.nullish,
            ...languageRules.cpp.nullish,
            ...languageRules.sql.nullish,
            ...languageRules.json.nullish,
            ...languageRules.arkts.nullish
        ])),
        extra: Array.from(new Set([
            ...languageRules.javascript.extra,
            ...languageRules.python.extra,
            ...languageRules.java.extra,
            ...languageRules.cpp.extra,
            ...languageRules.arkts.keywords
        ])),
        components: languageRules.arkts.components,
        decorators: languageRules.arkts.decorators
    };

    const rules = languageRules[language] || languageRules.default;

    // ------- Token 正则 -------
    const patterns = [];
    patterns.push({ type: 'comment', regex: /(\/\/.*|#.*|\/\*[\s\S]*?\*\/)/y });
    patterns.push({ type: 'string', regex: /(["'`])(?:\\.|(?!\1).)*\1/y });
    patterns.push({ type: 'number', regex: /\b\d+(\.\d+)?\b/y });

    if (rules.booleans?.length) {
        patterns.push({
            type: 'boolean',
            regex: new RegExp(`\\b(${rules.booleans.join('|')})\\b`, 'y')
        });
    }
    if (rules.nullish?.length) {
        patterns.push({
            type: 'nullish',
            regex: new RegExp(`\\b(${rules.nullish.join('|')})\\b`, 'y')
        });
    }
    if (rules.keywords?.length) {
        patterns.push({
            type: 'keyword',
            regex: new RegExp(`\\b(${rules.keywords.join('|')})\\b`, 'y')
        });
    }
    if (rules.types?.length) {
        patterns.push({
            type: 'type',
            regex: new RegExp(`\\b(${rules.types.join('|')})\\b`, 'y')
        });
    }

    if (rules.decorators?.length) {
        patterns.push({ type: 'decorator', regex: new RegExp(`(${rules.decorators.join('|')})(?=\\s|\\n|\\r)`, 'y') });
    } else {
        patterns.push({ type: 'decorator', regex: /@\w+/y });
    }

    if (rules.components?.length) {
        patterns.push({ type: 'component', regex: new RegExp(`\\b(${rules.components.join('|')})\\b`, 'y') });
    }

    patterns.push({ type: 'method', regex: /\b([a-zA-Z_][a-zA-Z0-9_]*)\s*(?=\()/y });
    patterns.push({ type: 'operator', regex: /[=+\-*/%<>!]=?|==|===|<=|>=|&&|\|\|/y });
    patterns.push({ type: 'brace', regex: /[()[\]]/y });
    patterns.push({ type: 'bigBrace', regex: /[{}]/y });
    patterns.push({ type: 'punctuation', regex: /[;,:.]/y });

    if (language === "html" || language === "default") {
        patterns.push({ type: 'doctype', regex: /<!DOCTYPE[^>]+>/iy });
        patterns.push({ type: 'tag', regex: /<\/?[a-zA-Z][^>\s>]*/y });
        patterns.push({ type: 'attrName', regex: /\s+[a-zA-Z\-:]+(?==)/y });
        patterns.push({ type: 'attrValue', regex: /(["'])(?:(?!\1).)*\1/y });
    }

    if (language === "css" || language === "default") {
        patterns.push({ type: 'attrName', regex: /[a-zA-Z-]+(?=\s*:)/y });
        patterns.push({ type: 'attrValue', regex: /:[^;]+/y });
    }

    // ------- 解析 -------
    return code.split('\n').map(line => {
        let row = [];
        let pos = 0;
        while (pos < line.length) {
            let matched = false;
            for (const { type, regex } of patterns) {
                regex.lastIndex = pos;
                const m = regex.exec(line);
                if (m && m.index === pos) {
                    row.push({ color: c[type], type, text: m[0] });
                    pos += m[0].length;
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                row.push({ color: c.normal, type: "normal", text: line[pos] });
                pos++;
            }
        }
        // 合并相邻同色
        let merged = [];
        for (const token of row) {
            if (merged.length && merged[merged.length - 1].color === token.color) {
                merged[merged.length - 1].text += token.text;
            } else {
                merged.push({ ...token });
            }
        }
        return { type: "row", code: merged };
    });
}
