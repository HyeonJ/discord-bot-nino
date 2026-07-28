// eslint.config.js — 정적 검사 배선
//
// 왜 이렇게 좁은가 (2026-07-28, Darren 승인 M:1t4b):
//   맨 처음 잰 값은 **296건**이었다. 분해해보니 291건이 위반이 아니라 *설정 구멍*이었다 —
//   `tests/**` 의 jest 전역(`describe`·`test`·`expect`…)을 선언하지 않아서 전부
//   `no-undef` 로 잡힌 것. 즉 그 296 은 코드 상태가 아니라 내 설정 상태를 재고 있었다.
//   ⇒ 규칙을 늘리기 전에 **전역을 정확히 선언**한다. 도구가 자기 설정 구멍을 코드 결함으로
//     보고하면, 사람은 곧 그 도구의 빨간불을 안 본다(헛빨간불 = 신호 소실).
//
// 🔑 켤 때의 순서: **0건이 된 다음에 켠다**(룬드와 합의 M:so62). 위반을 남겨두고 CI 에
//   붙이면 첫날부터 빨간불이 정상이 되고, 그 뒤 진짜 회귀가 묻힌다.
const globals = require("globals");

module.exports = [
    {
        // 추적하지 않는 트리는 검사 대상이 아니다 — 여기서 재도 고칠 주체가 없다
        ignores: [
            "node_modules/**",
            "backups/**",
            "logs/**",
            "of/cdm/**",
            "claude-config/**",
            "coverage/**",
        ],
    },
    {
        files: ["**/*.js"],
        languageOptions: {
            ecmaVersion: "latest",
            sourceType: "commonjs",
            globals: { ...globals.node },
        },
        linterOptions: {
            // 안 쓰는 `eslint-disable` 주석은 그 자체가 낡은 신호다 — 알려준다
            reportUnusedDisableDirectives: "error",
        },
        rules: {
            "no-unused-vars": ["error", {
                args: "after-used",
                // catch 에서 받은 뒤 안 쓰는 err 는 흔하고, 지우면 재던지기 맥락이 사라진다
                caughtErrors: "none",
                // `const { a, ...rest } = obj` 로 키를 덜어내는 관용구를 위반으로 보지 않는다
                ignoreRestSiblings: true,
            }],
            "no-undef": "error",
            "no-empty": ["error", { allowEmptyCatch: true }],
        },
    },
    {
        // jest 전역 — 이걸 빼면 시험 파일 하나가 수십 건의 거짓 위반을 만든다(위 291건의 정체)
        files: ["tests/**/*.js"],
        languageOptions: { globals: { ...globals.jest } },
    },
    // ⚠️ 브라우저 전역(`document`·`window`) 블록은 **넣지 않았다.** 넣으려다 재보니
    //    있으나 없으나 4건으로 같았다 — 추적되는 CDP 파일들은 페이지 코드를 문자열
    //    (`Runtime.evaluate` 인자)로만 갖고 있어서 eslint 가 파싱하지 않는다. 필요 없는
    //    설정은 그 자체로 낡은 신호가 되고, 전역을 열어두면 노드 파일의 `document` 오타를
    //    놓친다. 나중에 진짜 브라우저 파일이 추적되면 그때 그 파일만 지목해서 연다.
];
