#!/usr/bin/env node

/**
 * Repository Setup Test
 * 
 * Tests that the repository is properly configured and all
 * scripts work as expected without requiring live Supabase connection.
 */

import { readFileSync, existsSync } from 'fs';
import { execSync } from 'child_process';

console.log('🧪 Testing Repository Setup...\n');

const tests = [];
let passed = 0;
let failed = 0;

function test(name, fn) {
  tests.push({ name, fn });
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function runTest(testCase) {
  try {
    testCase.fn();
    console.log(`✅ ${testCase.name}`);
    passed++;
  } catch (error) {
    console.log(`❌ ${testCase.name}: ${error.message}`);
    failed++;
  }
}

// File structure tests
test('package.json exists and is valid', () => {
  assert(existsSync('package.json'), 'package.json not found');
  const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
  assert(pkg.name === 'supabase-sidecar-embedding-engine', 'Wrong package name');
  assert(pkg.scripts.seed, 'Missing seed script');
  assert(pkg.scripts.monitor, 'Missing monitor script');
  assert(pkg.scripts.performance, 'Missing performance script');
});

test('.env.example exists', () => {
  assert(existsSync('.env.example'), '.env.example not found');
  const envContent = readFileSync('.env.example', 'utf8');
  assert(envContent.includes('SUPABASE_URL'), 'Missing SUPABASE_URL in .env.example');
  assert(envContent.includes('SUPABASE_ANON_KEY'), 'Missing SUPABASE_ANON_KEY in .env.example');
});

test('README.md has setup instructions', () => {
  assert(existsSync('README.md'), 'README.md not found');
  const readmeContent = readFileSync('README.md', 'utf8');
  assert(readmeContent.includes('Quick Setup'), 'Missing setup instructions');
  assert(readmeContent.includes('npm install'), 'Missing npm install instructions');
});

test('All script files exist', () => {
  const requiredScripts = [
    'src/scripts/seed-sample-data.js',
    'src/scripts/monitor-queue.js', 
    'src/scripts/performance-test.js',
    'src/scripts/cost-analysis.js'
  ];
  
  requiredScripts.forEach(script => {
    assert(existsSync(script), `Missing script: ${script}`);
  });
});

test('Supabase functions exist', () => {
  const requiredFunctions = [
    'supabase/functions/process-embedding-queue/index.ts',
    'supabase/functions/manual-enqueue-embeddings/index.ts'
  ];
  
  requiredFunctions.forEach(func => {
    assert(existsSync(func), `Missing function: ${func}`);
  });
});

test('SQL migrations exist', () => {
  const requiredMigrations = [
    'supabase/migrations/001_source_documents_schema.sql',
    'supabase/migrations/002_document_embeddings_sidecar.sql',
    'supabase/migrations/003_embedding_queue_system.sql',
    'supabase/migrations/004_autonomous_reembedding_system.sql'
  ];
  
  requiredMigrations.forEach(migration => {
    assert(existsSync(migration), `Missing migration: ${migration}`);
  });
});

test('Dependencies are installed', () => {
  assert(existsSync('node_modules'), 'node_modules not found - run npm install');
  assert(existsSync('node_modules/@supabase/supabase-js'), 'Missing @supabase/supabase-js dependency');
});

test('Scripts run without environment errors', () => {
  // Test that scripts fail gracefully when environment is not set up
  try {
    execSync('npm run setup', { stdio: 'pipe' });
  } catch (error) {
    // Setup script should work (just prints message)
    throw new Error('Setup script failed');
  }
  
  // These should fail gracefully with env var error, not syntax errors
  const scriptsToTest = ['seed', 'monitor', 'performance', 'analyze:cost'];
  
  scriptsToTest.forEach(script => {
    try {
      execSync(`npm run ${script}`, { stdio: 'pipe' });
    } catch (error) {
      const stdout = error.stdout?.toString() || '';
      const stderr = error.stderr?.toString() || '';
      const output = stdout + stderr;
      // Should fail with env var error, not syntax error
      if (!output.includes('SUPABASE_URL') && !output.includes('environment') && 
          !output.includes('supabaseUrl is required') && !output.includes('Missing required environment')) {
        throw new Error(`Script ${script} failed with unexpected error: ${output.slice(0, 200)}`);
      }
    }
  });
});

test('Documentation is comprehensive', () => {
  const docsToCheck = [
    'docs/PERFORMANCE_METHODOLOGY.md',
    'docs/TECHNICAL_DEEP_DIVE.md'
  ];
  
  docsToCheck.forEach(doc => {
    assert(existsSync(doc), `Missing documentation: ${doc}`);
  });
});

// Run all tests
console.log('Running tests...\n');
tests.forEach(runTest);

console.log('\n📊 Test Results:');
console.log(`   Passed: ${passed}`);
console.log(`   Failed: ${failed}`);
console.log(`   Total:  ${tests.length}`);

if (failed === 0) {
  console.log('\n🎉 All tests passed! Repository is properly set up.');
  console.log('\n📋 Next Steps:');
  console.log('   1. Copy .env.example to .env');
  console.log('   2. Add your Supabase credentials to .env');
  console.log('   3. Set up your Supabase project (see README.md)');
  console.log('   4. Run: npm run seed');
  process.exit(0);
} else {
  console.log('\n❌ Some tests failed. Please fix the issues above.');
  process.exit(1);
}
